pid_file = "/tmp/pidfile"

vault {
  address = "http://vault:8200"
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path                   = "/vault/agent/config/role_id"
      secret_id_file_path                 = "/vault/agent/config/secret_id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink "file" {
    config = {
      path = "/vault/agent/token/.vault-token"
    }
  }
}

template {
  source      = "/vault/agent/templates/db-creds.ctmpl"
  destination = "/vault/secrets/db-creds.env"
  perms       = "0440"
}
