{{ if eq .Type "user" }{
  "type": {{ toJson .Type }},
  "keyId": {{ toJson .KeyID }},
  "principals": ["automation"],
  "extensions": {{ toJson .Extensions }},
  "criticalOptions": {{ toJson .CriticalOptions }}
}{{ else }}{{ fail "automation@internal signs user certificates only" }}{{ end }}
