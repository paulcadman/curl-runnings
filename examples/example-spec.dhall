-- Your curl-runnings specs can be written in dhall, which can give you great
-- type safety and interpolation abilities. Current drawbacks of the dhall
-- approach are that not all dhall features are available, since curl-runnings
-- turns your dhall spec into json and then parses it from there. As a result,
-- you can't do things like encode sum types in your dhall spec. However, a way
-- around this is to fully evaluate your dhall expressions, then call curl
-- runnings as a result.


    let host = "https://tabdextension.com"

in  let HttpMethod =
          constructors
          < DELETE : {} | GET : {} | PATCH : {} | POST : {} | PUT : {} >

in  [ { expectData    = { exactly = { ping = "$<SUITE[-1].ping>" } }
      , expectStatus  = +200
      , name          = "test 2"
      , requestMethod = HttpMethod.POST {=}
      , url           = host ++ "/ping"
      }
    , { expectData    = { exactly = { ping = "$<SUITE[-1].ping>" } }
      , expectStatus  = +200
      , name          = "test 2"
      , requestMethod = HttpMethod.POST {=}
      , url           = host ++ "/ping"
      }
    ]
