# --------------------------------------------------------------------------------
# MFA Enforcement Group (all users are auto-enrolled, see iam_users.tf)
# --------------------------------------------------------------------------------
#
# Denies almost every API call when the caller has not authenticated with MFA.
# Actions required to enable MFA on the user's own account are allowed, scoped
# to the caller's own user and MFA device via ${aws:username}.
#
# ref: https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_users-self-manage-mfa-and-creds.html

resource "aws_iam_group" "mfa_enforced" {
  name = "${var.project_name}-${var.environment}-mfa-enforced"
}

data "aws_iam_policy_document" "mfa_enforced" {
  # Allow each user to manage their own MFA device (scoped to self).
  statement {
    sid    = "AllowManageOwnVirtualMFADevice"
    effect = "Allow"

    actions = [
      "iam:CreateVirtualMFADevice",
      "iam:DeleteVirtualMFADevice",
    ]

    resources = ["arn:aws:iam::*:mfa/$${aws:username}"]
  }

  statement {
    sid    = "AllowManageOwnUserMFA"
    effect = "Allow"

    actions = [
      "iam:DeactivateMFADevice",
      "iam:EnableMFADevice",
      "iam:GetUser",
      "iam:ListMFADevices",
      "iam:ResyncMFADevice",
    ]

    resources = ["arn:aws:iam::*:user/$${aws:username}"]
  }

  statement {
    sid    = "AllowChangeOwnPassword"
    effect = "Allow"

    actions = [
      "iam:ChangePassword",
      "iam:GetAccountPasswordPolicy",
    ]

    resources = ["arn:aws:iam::*:user/$${aws:username}"]
  }

  # Deny every other API call when MFA is not present on the session.
  # Deny with Resource="*" is a safety mechanism, not a grant — security_prohibitions.md
  # 2.2.26-7 targets "付与" (grant), i.e. Allow statements. Deny is outside that rule.
  # Intentionally omits iam:ListVirtualMFADevices / sts:GetSessionToken to avoid
  # the Allow + Resource="*" pattern (see §6 of iam-design skill). Users can view
  # their own MFA via iam:ListMFADevices (scoped to self in AllowManageOwnUserMFA).
  statement {
    sid    = "DenyAllExceptListedIfNoMFA"
    effect = "Deny"

    not_actions = [
      "iam:CreateVirtualMFADevice",
      "iam:DeleteVirtualMFADevice",
      "iam:DeactivateMFADevice",
      "iam:EnableMFADevice",
      "iam:GetUser",
      "iam:ListMFADevices",
      "iam:ResyncMFADevice",
      "iam:ChangePassword",
      "iam:GetAccountPasswordPolicy",
    ]

    resources = ["*"]

    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_iam_group_policy" "mfa_enforced" {
  name   = "require-mfa"
  group  = aws_iam_group.mfa_enforced.id
  policy = data.aws_iam_policy_document.mfa_enforced.json
}
