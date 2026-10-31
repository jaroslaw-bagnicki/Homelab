{
{{ if ne .Type "host" }}{{ fail "hosts@internal signs host certificates only" }}{{ end }}
  "type": {{ toJson .Type }},
  "keyId": {{ toJson .KeyID }},
  "principals": {{ toJson .Principals }},
  "extensions": {{ toJson .Extensions }},
  "criticalOptions": {{ toJson .CriticalOptions }}
}
