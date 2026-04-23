locals {
  # lanes を「共通 WAF だけのもの」と「IP 制限付きのもの」に分ける
  lanes_base = {
    user = {}
  }

  lanes_ip_restricted = {
    admin = {
      ip_allowlist = [
        "203.0.113.0/24",
        "198.51.100.8/32",
      ]
    }
  }
}
