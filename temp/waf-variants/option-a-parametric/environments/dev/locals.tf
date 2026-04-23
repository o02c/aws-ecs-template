locals {
  # lanes: ip_allowlist をここで明示。空リスト = 制限なし。
  lanes = {
    user = {
      ip_allowlist = []
    }
    admin = {
      ip_allowlist = [
        "203.0.113.0/24", # corporate egress
        "198.51.100.8/32",
      ]
    }
  }
}
