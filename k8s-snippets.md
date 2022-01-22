## To get the values of secrets

`k get secret <secret_name> -o json | jq '.data| map_values(@base64d)'`