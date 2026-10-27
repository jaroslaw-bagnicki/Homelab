{{ if eq .Type "host" }{
  "type": {{ toJson .Type }},
  "keyId": {{ toJson .KeyID }},
  "principals": {{ toJson .Principals }},
  "extensions": {{ toJson .Extensions }},
  "criticalOptions": {{ toJson .CriticalOptions }}
}{{ else }}{{ fail "hosts@internal signs host certificates only" }}{{ end }}
