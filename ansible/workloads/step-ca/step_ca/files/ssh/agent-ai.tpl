{{ if eq .Type "user" }{
  "type": {{ toJson .Type }},
  "keyId": {{ toJson .KeyID }},
  "principals": ["agent-ai"],
  "extensions": {{ toJson .Extensions }},
  "criticalOptions": {{ toJson .CriticalOptions }}
}{{ else }}{{ fail "agent-ai@internal signs user certificates only" }}{{ end }}
