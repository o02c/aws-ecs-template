# WAF Variant Experiment

## 問題
CloudFront の WAF を lane（user / admin）ごとに作っている。
将来、**admin だけに IP 制限ルールを追加したい** という要求が出る想定。
user には IP 制限なし、admin には社内 IP のみ許可する。

## 評価軸
`.claude/skills/terraform-conventions/SKILL.md` の思想と整合しているか。主に：

- `§1` ファイル分割（100 行目安 / 責務分離 / 凝集優先）
- `§4` variable に default 書かない、文字列処理避ける、`for_each` + dynamic
- `§6` environments が UI、lanes は key で動く map（値は拡張フィールド）
- `§11` チェックリスト全般

加えて **将来の保守性**：
- 3 レーン目（例：partner）が増えたとき差分が最小か
- admin だけ別の rule（例：GEO block）を足したいときに追加コストが小さいか
- WAF module を別プロジェクトで流用しやすいか

## 2 案

### option-a-parametric
**1 つの `waf` module を parameter で分岐**。  
lane config（`locals.lanes`）に `ip_allowlist` を持たせ、module 内で `length(var.ip_allowlist) > 0` のとき dynamic で rule を足す。

### option-b-separate-modules
**`waf_base` と `waf_ip_restricted` の 2 module**。  
environments で `module "waf_base"` と `module "waf_ip_restricted"` を別々に呼び、lane ごとに使い分ける。
