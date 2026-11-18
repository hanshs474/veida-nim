import std/[json, os, strutils, unittest]
import veida

suite "veida SDK":
  test "buildGenerateBody defaults":
    let b = buildGenerateBody("a calm lake at sunrise")
    check b["provider"].getStr() == "kie"
    check b["mediaType"].getStr() == "image"
    check b["model"].getStr() == "veida-image-v1"
    check b["scene"].getStr() == "text-to-image"
    check b["options"]["aspect_ratio"].getStr() == "1:1"

  test "classifyGenerateResponse handles quota wall":
    let c = classifyGenerateResponse(200, """{"code":0,"data":{"wall":true,"reason":"ip_daily"}}""")
    check not c.ok
    check c.reason == rQuota

  test "classifyGenerateResponse handles task id":
    let c = classifyGenerateResponse(200, """{"code":0,"data":{"id":"task_123"}}""")
    check c.ok
    check c.taskId == "task_123"

  test "rejects empty prompt and invalid aspect ratio":
    let r1 = generate("   ")
    check not r1.ok
    var o = defaultOptions()
    o.aspectRatio = "21:9"
    let r2 = generate("test", o)
    check not r2.ok

  if getEnv("VEIDA_LIVE_TEST") == "1":
    test "live anonymous generation":
      let r = generate("minimalist ceramic cup on oak table, soft window light")
      echo "LIVE RESULT: ok=", r.ok, " reason=", r.reason, " msg=", r.message, " url=", r.imageUrl
      check r.ok or r.reason == rQuota
      if r.ok:
        check r.imageUrl.startsWith("https://")
