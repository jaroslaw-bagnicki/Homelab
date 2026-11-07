{
{{ if ne .Type "user" }}{{ fail "agent-ai@internal signs user certificates only" }}{{ end }}
  "type": {{ toJson .Type }},
  "keyId": {{ toJson .KeyID }},
  "principals": ["agent-ai"],
  "extensions": {{ toJson .Extensions }},
  "criticalOptions": {{ toJson .CriticalOptions }}
}
