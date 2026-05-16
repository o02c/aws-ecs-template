# app-resources

Repository-managed templates / startup config files for ECS tasks. The
contents of this directory are synced to the shared S3 bucket
`${project}-${env}-app-resources` by `scripts/deploy.sh app-resources`
(and as part of `scripts/full-deploy.sh`).

## Layout

- `common/` — shared across all lanes, every task role can read.
- `<lane>/` — readable only by tasks in that lane (enforced by IAM, see
  `terraform/project/modules/app/iam.tf::task_app_resources`).

Adding a new lane: drop a directory whose name matches the lane key in
`terraform/project/environments/<env>/locals.tf::services[*].lane`.

## Verification

After deploy, hit `GET /api/test/app-resources` (DEBUG only) on either
lane to see the startup-time read of `common/hello.txt` and
`<lane>/hello.txt`. Cross-lane reads should return `AccessDenied`:

```
# from user-api: succeeds
curl https://<domain>/api/test/app-resources?key=common/hello.txt
curl https://<domain>/api/test/app-resources?key=user/hello.txt

# from user-api: 403 AccessDenied
curl https://<domain>/api/test/app-resources?key=admin/hello.txt
```
