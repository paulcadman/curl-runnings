-- Your curl-runnings specs can be written in dhall, which can give you great
-- type safety and interpolation abilities.

    let host = "https://tabdextension.com"

in  [ { expectData    = { exactly = { ping = "$<SUITE[-1].ping>" } }
      , expectStatus  = +200
      , name          = "test 2"
      , requestMethod = "POST"
      , url           = host ++ "/ping"
      }
    ]
