## Official Nim SDK for Veida AI (https://veida.ai).
##
## Unlimited free AI image generator. Generate images from Nim with no API key
## on the anonymous free tier, or pass VEIDA_API_KEY from
## https://veida.ai/settings/apikeys to run on your own account.
##
## Compile with `-d:ssl` (enabled by `config.nims`).

import std/[httpclient, json, os, random, strutils, times, uri]

const
  BaseUrl* = "https://veida.ai"
  DefaultModel* = "veida-image-v1"
  SdkVersion* = "0.1.0"
  AspectRatios* = ["1:1", "16:9", "9:16", "4:3", "3:4"]

type
  Reason* = enum
    rNone = "none"
    rQuota = "quota"
    rRejected = "rejected"
    rAuth = "auth"
    rTimeout = "timeout"
    rOther = "other"

  Result* = object
    ok*: bool
    imageUrl*: string
    taskId*: string
    reason*: Reason
    message*: string

  Options* = object
    aspectRatio*: string
    apiKey*: string
    model*: string
    pollSeconds*: int
    timeoutSeconds*: int
    baseUrl*: string

proc defaultOptions*(): Options =
  Options(
    aspectRatio: "1:1",
    apiKey: "",
    model: DefaultModel,
    pollSeconds: 4,
    timeoutSeconds: 240,
    baseUrl: BaseUrl,
  )

proc fail(r: Reason, msg: string, taskId = ""): Result =
  Result(ok: false, reason: r, message: "veida: " & msg, taskId: taskId)

proc anonId(): string =
  randomize()
  result = "nim-"
  for _ in 1..8:
    result.add toHex(rand(255), 2).toLowerAscii

proc keyOf(o: Options): string =
  if o.apiKey.len > 0: o.apiKey.strip()
  else: getEnv("VEIDA_API_KEY").strip()

proc baseOf(o: Options): string =
  let b = if o.baseUrl.len > 0: o.baseUrl else: getEnv("VEIDA_BASE_URL", BaseUrl)
  b.strip(trailing = true, chars = {'/'})

proc buildGenerateBody*(prompt: string, opts = defaultOptions()): JsonNode =
  let ratio = if opts.aspectRatio.len > 0: opts.aspectRatio else: "1:1"
  let k = keyOf(opts)
  let model = if k.len > 0 and opts.model.len > 0: opts.model else: DefaultModel
  %*{
    "provider": "kie",
    "mediaType": "image",
    "model": model,
    "scene": "text-to-image",
    "prompt": prompt,
    "options": {
      "aspect_ratio": ratio
    }
  }

proc classifyGenerateResponse*(httpStatus: int, body: string): tuple[ok: bool, taskId: string, reason: Reason, msg: string] =
  var j: JsonNode
  try:
    j = parseJson(body)
  except CatchableError:
    let r = if httpStatus == 401: rAuth else: rOther
    return (false, "", r, "HTTP " & $httpStatus)

  if httpStatus == 401:
    let msg = if j.hasKey("message"): j["message"].getStr() else: "Invalid API key"
    return (false, "", rAuth, msg)

  let code = if j.hasKey("code"): j["code"].getInt() else: -1
  let msg = if j.hasKey("message"): j["message"].getStr() else: ""
  if j.hasKey("data") and j["data"].kind == JObject:
    let d = j["data"]
    if d.hasKey("wall") and d["wall"].kind == JBool and d["wall"].getBool():
      let why = if d.hasKey("reason"): d["reason"].getStr() else: ""
      if why == "ip_daily":
        return (false, "", rQuota, "per-IP daily free limit spent; set VEIDA_API_KEY or visit https://veida.ai/pricing")
      return (false, "", rQuota, "free allowance spent; set VEIDA_API_KEY or visit https://veida.ai/pricing")
    if code == 0 and d.hasKey("id") and d["id"].getStr().len > 0:
      return (true, d["id"].getStr(), rNone, "")

  if code == -2 or code == -3 or "refus" in msg.toLowerAscii():
    return (false, "", rRejected, if msg.len > 0: msg else: "prompt refused by content filter")
  if httpStatus >= 400 or code != 0:
    return (false, "", rOther, if msg.len > 0: msg else: "HTTP " & $httpStatus)
  (false, "", rOther, "API returned no task id")

proc requestHeaders(key, anon: string): HttpHeaders =
  if key.len > 0:
    newHttpHeaders({
      "Content-Type": "application/json",
      "Authorization": "Bearer " & key,
      "User-Agent": "veida-nim/" & SdkVersion,
    })
  else:
    newHttpHeaders({
      "Content-Type": "application/json",
      "x-anon-id": anon,
      "User-Agent": "veida-nim/" & SdkVersion,
    })

proc generate*(prompt: string, opts = defaultOptions()): Result =
  if prompt.strip().len == 0:
    return fail(rOther, "prompt is required")
  let ratio = if opts.aspectRatio.len > 0: opts.aspectRatio else: "1:1"
  if ratio notin AspectRatios:
    return fail(rOther, "aspectRatio must be one of 1:1, 16:9, 9:16, 4:3, 3:4")

  let key = keyOf(opts)
  let anon = anonId()
  let base = baseOf(opts)
  let client = newHttpClient(timeout = 60000)
  defer: client.close()

  client.headers = requestHeaders(key, anon)
  let body = buildGenerateBody(prompt, opts)
  let subResp = client.request(base & "/api/ai/generate", httpMethod = HttpPost, body = $body)
  let parsed = classifyGenerateResponse(subResp.code.int, subResp.body)
  if not parsed.ok:
    return fail(parsed.reason, parsed.msg)

  let taskId = parsed.taskId
  let pollSec = if opts.pollSeconds > 0: opts.pollSeconds else: 4
  let timeoutSec = if opts.timeoutSeconds > 0: opts.timeoutSeconds else: 240
  let deadline = getTime() + initDuration(seconds = timeoutSec)

  while getTime() < deadline:
    sleep(pollSec * 1000)
    client.headers = requestHeaders(key, anon)
    var pollBody = ""
    if key.len > 0:
      let r = client.request(base & "/api/ai/query", httpMethod = HttpPost, body = $(%*{"taskId": taskId}))
      pollBody = r.body
    else:
      let qUrl = base & "/api/ai/anon-query?taskId=" & encodeUrl(taskId) & "&provider=kie&mediaType=image"
      let r = client.request(qUrl, httpMethod = HttpGet)
      pollBody = r.body

    var pj: JsonNode
    try:
      pj = parseJson(pollBody)
    except CatchableError:
      continue

    if pj.hasKey("data") and pj["data"].kind == JObject:
      let d = pj["data"]
      for field in ["cleanImages", "images"]:
        if d.hasKey(field) and d[field].kind == JArray and d[field].len > 0:
          let u = d[field][0].getStr()
          if u.len > 0:
            return Result(ok: true, imageUrl: u, taskId: taskId, reason: rNone, message: "")
      let st = if d.hasKey("status") and d["status"].kind == JString: d["status"].getStr().toLowerAscii() else: ""
      if st == "failed" or st == "error":
        return fail(rRejected, "prompt refused by content filter; reword it", taskId)

  fail(rTimeout, "still queued after " & $timeoutSec & "s", taskId)
