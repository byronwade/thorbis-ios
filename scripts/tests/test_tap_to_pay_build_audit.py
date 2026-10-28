import importlib.util
from pathlib import Path
import unittest


module_path = Path(__file__).parents[1] / "audit_tap_to_pay_build.py"
spec = importlib.util.spec_from_file_location("tap_build_audit", module_path)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

KEY = "com.apple.developer.proximity-reader.payment.acceptance"


class TapBuildAuditTests(unittest.TestCase):
    def test_disabled_build_needs_no_reader_grant(self):
        self.assertEqual(audit.validate(False, {}, {}), [])

    def test_missing_build_policy_does_not_certify_a_legacy_binary(self):
        self.assertTrue(audit.validate(None, {}, {}))

    def test_enabled_policy_cannot_replace_a_signed_entitlement(self):
        self.assertTrue(audit.validate(True, {}, {KEY: True}))

    def test_signed_claim_needs_a_profile_allowance(self):
        self.assertTrue(audit.validate(True, {KEY: True}, {}))

    def test_only_boolean_grants_count(self):
        self.assertTrue(audit.validate(True, {KEY: "true"}, {KEY: True}))
        self.assertTrue(audit.validate(True, {KEY: True}, {KEY: 1}))

    def test_matching_signed_and_profile_grants_pass(self):
        self.assertEqual(audit.validate(True, {KEY: True}, {KEY: True}), [])

    def binding(self):
        signed = {"application-identifier": "TEAM.com.thorbis.field",
                  "com.apple.developer.team-identifier": "TEAM", "get-task-allow": False}
        profile = {"TeamIdentifier": ["TEAM"], "Entitlements": {
            "application-identifier": "TEAM.com.thorbis.field", "get-task-allow": False,
            "beta-reports-active": True}}
        return {"CFBundleIdentifier": "com.thorbis.field"}, signed, profile

    def test_matching_distribution_identity_passes(self):
        self.assertEqual(audit.validate_binding(*self.binding(), distribution=True), [])

    def test_a_grant_for_another_app_or_team_is_refused(self):
        info, signed, profile = self.binding()
        profile["Entitlements"]["application-identifier"] = "TEAM.com.other.app"
        self.assertTrue(audit.validate_binding(info, signed, profile))
        info, signed, profile = self.binding()
        profile["TeamIdentifier"] = ["OTHER"]
        self.assertTrue(audit.validate_binding(info, signed, profile))

    def test_development_profile_is_not_distribution_approval(self):
        info, signed, profile = self.binding()
        signed["get-task-allow"] = True
        profile["Entitlements"]["get-task-allow"] = True
        self.assertTrue(audit.validate_binding(info, signed, profile, distribution=True))


if __name__ == "__main__":
    unittest.main()
