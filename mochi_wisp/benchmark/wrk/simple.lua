wrk.method = "POST"
wrk.body   = '{"query":"{ users { id name } }"}'
wrk.headers["Content-Type"] = "application/json"
