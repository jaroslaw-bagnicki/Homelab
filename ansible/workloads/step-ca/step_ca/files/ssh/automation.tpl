{
{{ if ne .Type "user" }}{{ fail "automation@internal signs user certificates only" }}{{ end }}
  "type": {{ toJson .Type }},
  "keyId": {{ toJson .KeyID }},
  "principals": ["automation"],
  "extensions": {{ toJson .Extensions }},
  "criticalOptions": {{ toJson .CriticalOptions }}
}
