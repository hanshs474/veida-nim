# veida-nim

Unlimited free AI image generator. Sign in with Google to make pictures and edit your own photos on Veida AI Image v1 with no limit and no card. Official Nim SDK for [Veida AI](https://veida.ai/?utm_source=nimble&utm_medium=package).

Works with no API key on the anonymous free tier, or set `VEIDA_API_KEY` from [veida.ai/settings/apikeys](https://veida.ai/settings/apikeys) to run on your own account.

## Install

```sh
nimble install veida
```

## Quick start

```nim
import veida

let res = generate("warm sunlight through a cafe window, 35mm photo")
if res.ok:
  echo res.imageUrl
else:
  echo res.reason, ": ", res.message
```

Pass an API key or a different aspect ratio (`"1:1"`, `"16:9"`, `"9:16"`, `"4:3"`, `"3:4"`):

```nim
import veida

var opts = defaultOptions()
opts.aspectRatio = "16:9"
opts.apiKey = "sk-..." # or set VEIDA_API_KEY
opts.model = "veida-image-v1"

let res = generate("ceramic mug on pale oak", opts)
if res.ok:
  echo res.imageUrl
```

Web links:
- [ChatGPT Image Generator](https://veida.ai/image/chatgpt-image-generator)
- [AI Image Hub](https://veida.ai/image)
- [Plans & Pricing](https://veida.ai/pricing)

## License

MIT
