module Fixtures.Captured exposing
    ( ccaaMonth2024JanFeb
    , ccaaYear2014To2018
    , error400TimeTruncHour
    , error500TimeTruncDayHtml
    , error502InvalidGeoId
    )

{-| Real REData responses, captured from the live API on 2026-09-04 and reproduced here
verbatim.

**Everything in this module is genuine captured output.** Hand-written fixtures live in
`Fixtures.Synthetic` instead, and the two are kept in separate modules precisely so that
a reader never has to check which kind a given fixture is. Evidence and construction
support very different claims, and a test suite should never blur which one it is
resting on.

Why the bodies are inlined as strings rather than read from files at test time:
`elm-test` runs compiled Elm with no filesystem access, so there is no runtime read to
do. The only alternatives are a codegen step in the build or a literal — and a
literal that a reviewer can read in the same file as the test is worth more here than a
generator that has to be trusted.

The one transformation applied: each `\` in the capture is written `\\` in this
source, because the captures escape their accented characters as `\u00f3` and Elm does
not accept `\u` as an escape. The decoded string is byte-identical to what the API
returned.

-}


{-| `geo_ids=7` (Castilla-La Mancha), `time_trunc=year`, 2014–2018.

The awkward capture, and the reason it is the main decoder fixture:

  - **A ragged series.** Nine technologies have five values each; `Carbón` has three.
    It has no 2017 and no 2018 entry at all — no null, no zero, simply absent.
  - **A negative value.** `Carbón` in 2016 is `-2005.081`.
  - **A total row**, `Generación total`, carrying `attributes.type == "total"`.

-}
ccaaYear2014To2018 : String
ccaaYear2014To2018 =
    """{"data":{"type":"Generaci\\u00f3n por tecnolog\\u00eda","id":"gen1","attributes":{"title":"Generaci\\u00f3n por tecnolog\\u00eda","last-update":"2019-06-12T17:00:43.000+02:00","description":null},"meta":{"cache-control":{"cache":"HIT","expireAt":"2026-10-04T09:47:35"}}},"included":[{"type":"Hidr\\u00e1ulica","id":"10330","groupId":"1","attributes":{"title":"Hidr\\u00e1ulica","description":null,"color":"#0090d1","icon":null,"type":"Renovable","magnitude":null,"composite":false,"last-update":"2019-06-20T14:17:29.000+02:00","values":[{"value":1006208.552,"percentage":0.02241407319348617,"datetime":"2014-01-01T00:00:00.000+01:00"},{"value":700914.375,"percentage":0.01625873037408754,"datetime":"2015-01-01T00:00:00.000+01:00"},{"value":731944.331,"percentage":0.01723281779508495,"datetime":"2016-01-01T00:00:00.000+01:00"},{"value":410077.844,"percentage":0.009586761724716656,"datetime":"2017-01-01T00:00:00.000+01:00"},{"value":768189.817,"percentage":0.017753076349694166,"datetime":"2018-01-01T00:00:00.000+01:00"}]}},{"type":"Nuclear","id":"1695","groupId":"1","attributes":{"title":"Nuclear","description":null,"color":"#464394","icon":null,"type":"No-Renovable","magnitude":null,"composite":false,"last-update":"2019-06-20T14:17:30.000+02:00","values":[{"value":7770076.699,"percentage":0.1730844639555274,"datetime":"2014-01-01T00:00:00.000+01:00"},{"value":7913818.669,"percentage":0.18357255687428486,"datetime":"2015-01-01T00:00:00.000+01:00"},{"value":7992498.721,"percentage":0.18817452141239754,"datetime":"2016-01-01T00:00:00.000+01:00"},{"value":7971229.695,"percentage":0.18635066696983227,"datetime":"2017-01-01T00:00:00.000+01:00"},{"value":7714455.597,"percentage":0.17828317452152126,"datetime":"2018-01-01T00:00:00.000+01:00"}]}},{"type":"Carb\\u00f3n","id":"10331","groupId":"1","attributes":{"title":"Carb\\u00f3n","description":null,"color":"#993300","icon":null,"type":"No-Renovable","magnitude":null,"composite":false,"last-update":"2019-06-20T14:17:29.000+02:00","values":[{"value":873047.18,"percentage":0.019447800711881343,"datetime":"2014-01-01T00:00:00.000+01:00"},{"value":894928.56,"percentage":0.020759172132987606,"datetime":"2015-01-01T00:00:00.000+01:00"},{"value":-2005.081,"percentage":4.720740918941105e-5,"datetime":"2016-01-01T00:00:00.000+01:00"}]}},{"type":"Ciclo combinado","id":"1703","groupId":"1","attributes":{"title":"Ciclo combinado","description":null,"color":"#ffcc66","icon":null,"type":"No-Renovable","magnitude":null,"composite":false,"last-update":"2019-11-29T14:16:11.000+01:00","values":[{"value":1035669.191,"percentage":0.023070331697312596,"datetime":"2014-01-01T00:00:00.000+01:00"},{"value":1280686.57,"percentage":0.029707391341980954,"datetime":"2015-01-01T00:00:00.000+01:00"},{"value":1258162.343,"percentage":0.02962203749011095,"datetime":"2016-01-01T00:00:00.000+01:00"},{"value":1658072.074,"percentage":0.03876225484604519,"datetime":"2017-01-01T00:00:00.000+01:00"},{"value":1401749.725,"percentage":0.032394818754916926,"datetime":"2018-01-01T00:00:00.000+01:00"}]}},{"type":"E\\u00f3lica","id":"10333","groupId":"1","attributes":{"title":"E\\u00f3lica","description":null,"color":"#6fb114","icon":null,"type":"Renovable","magnitude":null,"composite":false,"last-update":"2019-06-20T14:17:29.000+02:00","values":[{"value":8390570.682,"percentage":0.1869064470060946,"datetime":"2014-01-01T00:00:00.000+01:00"},{"value":7286716.406,"percentage":0.1690260060047908,"datetime":"2015-01-01T00:00:00.000+01:00"},{"value":7680537.222,"percentage":0.18082973377806505,"datetime":"2016-01-01T00:00:00.000+01:00"},{"value":7507167.263,"percentage":0.17550185856413716,"datetime":"2017-01-01T00:00:00.000+01:00"},{"value":8075036.159,"percentage":0.18661628973046918,"datetime":"2018-01-01T00:00:00.000+01:00"}]}},{"type":"Solar fotovoltaica","id":"1707","groupId":"1","attributes":{"title":"Solar fotovoltaica","description":null,"color":"#e48500","icon":null,"type":"Renovable","magnitude":null,"composite":false,"last-update":"2019-11-29T14:16:13.000+01:00","values":[{"value":1689431.18,"percentage":0.03763338529434175,"datetime":"2014-01-01T00:00:00.000+01:00"},{"value":1722910.268,"percentage":0.039965414471858855,"datetime":"2015-01-01T00:00:00.000+01:00"},{"value":1624757.124,"percentage":0.03825310517933125,"datetime":"2016-01-01T00:00:00.000+01:00"},{"value":1744799.365,"percentage":0.04078975739467633,"datetime":"2017-01-01T00:00:00.000+01:00"},{"value":1580628.938,"percentage":0.03652876619275729,"datetime":"2018-01-01T00:00:00.000+01:00"}]}},{"type":"Solar t\\u00e9rmica","id":"1708","groupId":"1","attributes":{"title":"Solar t\\u00e9rmica","description":null,"color":"#ff0000","icon":null,"type":"Renovable","magnitude":null,"composite":false,"last-update":"2019-06-20T14:17:30.000+02:00","values":[{"value":734252.687,"percentage":0.016356046106167355,"datetime":"2014-01-01T00:00:00.000+01:00"},{"value":735486.298,"percentage":0.01706067650990579,"datetime":"2015-01-01T00:00:00.000+01:00"},{"value":721879.998,"percentage":0.01699586423253586,"datetime":"2016-01-01T00:00:00.000+01:00"},{"value":742678.029,"percentage":0.01736225793804458,"datetime":"2017-01-01T00:00:00.000+01:00"},{"value":650078.076,"percentage":0.01502348177636711,"datetime":"2018-01-01T00:00:00.000+01:00"}]}},{"type":"Otras renovables","id":"10334","groupId":"1","attributes":{"title":"Otras renovables","description":null,"color":"#9a5cbc","icon":null,"type":"Renovable","magnitude":null,"composite":false,"last-update":"2019-06-20T14:17:29.000+02:00","values":[{"value":227923.774,"percentage":0.0050771782279302275,"datetime":"2014-01-01T00:00:00.000+01:00"},{"value":252176.13,"percentage":0.005849592832863284,"datetime":"2015-01-01T00:00:00.000+01:00"},{"value":238410.359,"percentage":0.005613107586330621,"datetime":"2016-01-01T00:00:00.000+01:00"},{"value":265550.596,"percentage":0.006208017153222489,"datetime":"2017-01-01T00:00:00.000+01:00"},{"value":272094.336,"percentage":0.006288174373609717,"datetime":"2018-01-01T00:00:00.000+01:00"}]}},{"type":"Cogeneraci\\u00f3n","id":"10335","groupId":"1","attributes":{"title":"Cogeneraci\\u00f3n","description":null,"color":"#cfa2ca","icon":null,"type":"No-Renovable","magnitude":null,"composite":false,"last-update":"2019-06-20T14:17:29.000+02:00","values":[{"value":718730.339,"percentage":0.016010273807258526,"datetime":"2014-01-01T00:00:00.000+01:00"},{"value":767378.364,"percentage":0.01780045945724027,"datetime":"2015-01-01T00:00:00.000+01:00"},{"value":988741.079,"percentage":0.023278812526143732,"datetime":"2016-01-01T00:00:00.000+01:00"},{"value":1088139.556,"percentage":0.0254384254093254,"datetime":"2017-01-01T00:00:00.000+01:00"},{"value":1173167.377,"percentage":0.027112218300664404,"datetime":"2018-01-01T00:00:00.000+01:00"}]}},{"type":"Generaci\\u00f3n total","id":"10338","groupId":"1","attributes":{"title":"Generaci\\u00f3n total","description":null,"color":"#2b2e34","icon":null,"type":"total","magnitude":null,"composite":false,"last-update":"2019-06-20T14:17:29.000+02:00","values":[{"value":22445910.284,"percentage":1,"datetime":"2014-01-01T00:00:00.000+01:00"},{"value":21555015.64,"percentage":1,"datetime":"2015-01-01T00:00:00.000+01:00"},{"value":21234926.096,"percentage":1,"datetime":"2016-01-01T00:00:00.000+01:00"},{"value":21387714.422,"percentage":1,"datetime":"2017-01-01T00:00:00.000+01:00"},{"value":21635400.025,"percentage":1,"datetime":"2018-01-01T00:00:00.000+01:00"}]}}]}"""


{-| `geo_ids=7`, `time_trunc=month`, January and February 2024.

Two buckets in one response, which is what makes it useful: it can tell a decoder that
picks the requested month apart from one that picks the first entry it finds.

-}
ccaaMonth2024JanFeb : String
ccaaMonth2024JanFeb =
    """{"data":{"type":"Generaci\\u00f3n por tecnolog\\u00eda","id":"gen1","attributes":{"title":"Generaci\\u00f3n por tecnolog\\u00eda","last-update":"2025-01-28T16:56:22.000+01:00","description":null},"meta":{"cache-control":{"cache":"MISS"}}},"included":[{"type":"Hidr\\u00e1ulica","id":"10330","groupId":"1","attributes":{"title":"Hidr\\u00e1ulica","description":null,"color":"#0090d1","icon":null,"type":"Renovable","magnitude":null,"composite":false,"last-update":"2026-02-12T09:31:50.000+01:00","values":[{"value":67854.941,"percentage":0.014056886663674304,"datetime":"2024-01-01T00:00:00.000+01:00"},{"value":66264.144,"percentage":0.012512279568933238,"datetime":"2024-02-01T00:00:00.000+01:00"}]}},{"type":"Nuclear","id":"1695","groupId":"1","attributes":{"title":"Nuclear","description":null,"color":"#464394","icon":null,"type":"No-Renovable","magnitude":null,"composite":false,"last-update":"2026-02-12T09:32:52.000+01:00","values":[{"value":733454.595,"percentage":0.15194307095287485,"datetime":"2024-01-01T00:00:00.000+01:00"},{"value":610840.15,"percentage":0.1153414541766225,"datetime":"2024-02-01T00:00:00.000+01:00"}]}},{"type":"Ciclo combinado","id":"1703","groupId":"1","attributes":{"title":"Ciclo combinado","description":null,"color":"#ffcc66","icon":null,"type":"No-Renovable","magnitude":null,"composite":false,"last-update":"2026-02-12T09:32:52.000+01:00","values":[{"value":139673.72,"percentage":0.028934925342191057,"datetime":"2024-01-01T00:00:00.000+01:00"},{"value":86061.33,"percentage":0.016250469047547362,"datetime":"2024-02-01T00:00:00.000+01:00"}]}},{"type":"E\\u00f3lica","id":"10333","groupId":"1","attributes":{"title":"E\\u00f3lica","description":null,"color":"#6fb114","icon":null,"type":"Renovable","magnitude":null,"composite":false,"last-update":"2026-02-12T09:31:51.000+01:00","values":[{"value":934657.379,"percentage":0.19362440895748298,"datetime":"2024-01-01T00:00:00.000+01:00"},{"value":1177861.186,"percentage":0.22240879551129902,"datetime":"2024-02-01T00:00:00.000+01:00"}]}},{"type":"Solar fotovoltaica","id":"1707","groupId":"1","attributes":{"title":"Solar fotovoltaica","description":null,"color":"#e48500","icon":null,"type":"Renovable","magnitude":null,"composite":false,"last-update":"2026-02-12T09:32:52.000+01:00","values":[{"value":446895.804,"percentage":0.09257931072844947,"datetime":"2024-01-01T00:00:00.000+01:00"},{"value":605989.716,"percentage":0.11442557444778062,"datetime":"2024-02-01T00:00:00.000+01:00"}]}},{"type":"Solar t\\u00e9rmica","id":"1708","groupId":"1","attributes":{"title":"Solar t\\u00e9rmica","description":null,"color":"#ff0000","icon":null,"type":"Renovable","magnitude":null,"composite":false,"last-update":"2026-02-12T09:32:52.000+01:00","values":[{"value":6934.932,"percentage":0.0014366463474529904,"datetime":"2024-01-01T00:00:00.000+01:00"},{"value":21973.706,"percentage":0.0041491693099898145,"datetime":"2024-02-01T00:00:00.000+01:00"}]}},{"type":"Otras renovables","id":"10334","groupId":"1","attributes":{"title":"Otras renovables","description":null,"color":"#9a5cbc","icon":null,"type":"Renovable","magnitude":null,"composite":false,"last-update":"2026-02-12T09:31:51.000+01:00","values":[{"value":9389.505,"percentage":0.0019451377551563,"datetime":"2024-01-01T00:00:00.000+01:00"},{"value":14947.103,"percentage":0.002822376027096052,"datetime":"2024-02-01T00:00:00.000+01:00"}]}},{"type":"Cogeneraci\\u00f3n","id":"10335","groupId":"1","attributes":{"title":"Cogeneraci\\u00f3n","description":null,"color":"#cfa2ca","icon":null,"type":"No-Renovable","magnitude":null,"composite":false,"last-update":"2026-02-12T09:31:51.000+01:00","values":[{"value":74722.68,"percentage":0.015479613252718067,"datetime":"2024-01-01T00:00:00.000+01:00"},{"value":64027.156,"percentage":0.012089881910731409,"datetime":"2024-02-01T00:00:00.000+01:00"}]}},{"type":"Generaci\\u00f3n total","id":"10338","groupId":"1","attributes":{"title":"Generaci\\u00f3n total","description":null,"color":"#2b2e34","icon":null,"type":"total","magnitude":null,"composite":false,"last-update":"2026-02-12T09:31:51.000+01:00","values":[{"value":2413583.556,"percentage":1,"datetime":"2024-01-01T00:00:00.000+01:00"},{"value":2647964.491,"percentage":1,"datetime":"2024-02-01T00:00:00.000+01:00"}]}}]}"""


{-| The body of a real **400** (`time_trunc=hour` at CCAA level): the JSON `errors[]`
envelope.

Present in the tests to prove it is _not_ read. Its `detail` — "Inténtelo de nuevo más
tarde" — is the misleading text `Domain.RemoteData` refuses to surface.

-}
error400TimeTruncHour : String
error400TimeTruncHour =
    """{"errors":[{"status":"400","title":"Error Interno","detail":"Los datos solicitados no est\\u00e1n disponibles en este momento. Int\\u00e9ntelo de nuevo m\\u00e1s tarde."}]}"""


{-| The body of a real **502** (unknown `geo_ids`). Byte-identical to the 400 above
apart from the status field — which is the point: the body carries no information the
status code does not already give us, and the "try again later" advice is false for a
502 that is permanently cached upstream.
-}
error502InvalidGeoId : String
error502InvalidGeoId =
    """{"errors":[{"status":"502","title":"Error Interno","detail":"Los datos solicitados no est\\u00e1n disponibles en este momento. Int\\u00e9ntelo de nuevo m\\u00e1s tarde."}]}"""


{-| The body of a real **500** (`time_trunc=day` at CCAA level): an HTML Symfony error
page, not JSON.

This is the fixture that justifies `Api.Request.interpretResponse` never looking at an
error body. Handed to `Json.Decode.decodeString` it produces a decode failure, and the
user would be told the response was malformed when the real answer is "REData returned
a 500".

-}
error500TimeTruncDayHtml : String
error500TimeTruncDayHtml =
    """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8" />
    <meta name="robots" content="noindex,nofollow,noarchive" />
    <title>An Error Occurred: Internal Server Error</title>
    <style>body { background-color: #fff; color: #222; font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; margin: 0; }
.container { margin: 30px; max-width: 600px; }
h1 { color: #dc3545; font-size: 24px; }
h2 { font-size: 18px; }</style>
</head>
<body>
<div class="container">
    <h1>Oops! An Error Occurred</h1>
    <h2>The server returned a "500 Internal Server Error".</h2>

    <p>
        Something is broken. Please let us know what you were doing when this error occurred.
        We will fix it as soon as possible. Sorry for any inconvenience caused.
    </p>
</div>
</body>
</html>"""
