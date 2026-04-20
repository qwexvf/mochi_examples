wrk.method = "POST"
wrk.body   = '{"query":"{ users { id name email posts { id title } } }"}'
wrk.headers["Content-Type"] = "application/json"
