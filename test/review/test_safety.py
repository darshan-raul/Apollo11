"""Exercise destructive-script boundaries with fake CLI tools; no cluster/AWS calls."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SafetyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)
        self.log = self.work / 'calls'
        self.env = dict(os.environ, PATH=f'{self.work}:{os.environ["PATH"]}',
                        CALL_LOG=str(self.log), FAKE_CONTEXT='arn:aws:eks:unsafe')
        self.env.pop('KUBE_CONTEXT', None)

    def tool(self, name, code):
        p = self.work / name
        p.write_text('#!/bin/bash\nset -eu\n' + code)
        p.chmod(0o755)

    def run_script(self, path, *args):
        return subprocess.run(['bash', str(ROOT / path), *args], env=self.env,
                              capture_output=True, text=True)

    def calls(self):
        return self.log.read_text() if self.log.exists() else ''

    def test_teardown_rejects_cloud_context_before_mutation(self):
        self.tool('kubectl', 'echo "$*" >> "$CALL_LOG"\nif [[ "$*" == "config current-context" ]]; then echo "$FAKE_CONTEXT"; else exit 97; fi\n')
        self.tool('helm', 'echo "HELM $*" >> "$CALL_LOG"; exit 97\n')
        for stage in (5, 6, 7):
            result = self.run_script(f'stages/stage{stage}/scripts/teardown.sh', '--purge')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Refusing context', result.stderr)
        self.assertNotIn('delete', self.calls())
        self.assertNotIn('HELM', self.calls())

    def test_checked_context_is_passed_to_both_tools(self):
        self.env['KUBE_CONTEXT'] = 'kind-apollo11-dev'
        self.tool('kubectl', 'echo "KUBE $*" >> "$CALL_LOG"\n')
        self.tool('helm', 'echo "HELM $*" >> "$CALL_LOG"\n')
        script = f'source "{ROOT}/stages/stage5/scripts/context.sh"; apollo_context_guard; kubectl get ns; helm list'
        result = subprocess.run(['bash', '-c', script], env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn('KUBE --context kind-apollo11-dev get ns', self.calls())
        self.assertIn('HELM --kube-context kind-apollo11-dev list', self.calls())

    def early_stage_teardown_kubectl(self, foreign_route):
        # Fake cluster: the Stage namespaces are gone, the platform CRDs remain,
        # and optionally another team's HTTPRoute still uses them.
        route = 'other-team/other-app' if foreign_route else ''
        self.tool('kubectl', f"""echo "$*" >> "$CALL_LOG"
case "$*" in
  *"get crd -o name"*) echo customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io ;;
  *"get httproutes.gateway.networking.k8s.io -A"*) [[ -z "{route}" ]] || echo "{route}" ;;
  *"get namespace"*) exit 1 ;;
esac
""")

    def test_early_teardown_keeps_crds_used_outside_the_stage(self):
        self.early_stage_teardown_kubectl(foreign_route=True)
        for stage in (2, 3, 4):
            self.log.unlink(missing_ok=True)
            result = self.run_script(f'stages/stage{stage}/scripts/teardown.sh', 'kind-apollo11')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('other-team/other-app', result.stderr)
            self.assertNotIn('delete customresourcedefinition', self.calls())
            self.assertNotIn('metallb-system:controller', self.calls())

    def test_early_teardown_removes_owned_platform_when_unused(self):
        self.early_stage_teardown_kubectl(foreign_route=False)
        for stage in (2, 3, 4):
            self.log.unlink(missing_ok=True)
            self.run_script(f'stages/stage{stage}/scripts/teardown.sh', 'kind-apollo11')
            self.assertIn('delete customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io', self.calls())
            self.assertIn('delete clusterrole metallb-system:controller', self.calls())

    def test_certificate_rejects_cloud_context(self):
        result = self.run_script('stages/stage3/scripts/generate-certs.sh', '--context', 'arn:aws:eks:unsafe')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Refusing certificate changes', result.stderr)
        self.assertEqual(self.calls(), '')

    def test_certificate_uses_selected_context_and_preserves_existing_secret(self):
        self.tool('kubectl', 'echo "$*" >> "$CALL_LOG"\nif [[ "$*" == *"get secret"* ]]; then echo secret/apollo-tls-secret; fi\n')
        result = self.run_script('stages/stage3/scripts/generate-certs.sh', '--context', 'kind-apollo11-dev')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Preserving', result.stdout)
        self.assertNotIn('apply', self.calls())
        self.assertTrue(all(line.startswith('--context kind-apollo11-dev ') for line in self.calls().splitlines()))

    def test_platform_purge_rejects_foreign_route_before_deleting_crds(self):
        self.env['KUBE_CONTEXT'] = 'kind-apollo11'
        self.tool('kubectl', """echo "$*" >> "$CALL_LOG"
if [[ "$*" == *"get crd"* ]]; then
  echo httproutes.gateway.networking.k8s.io
else
  echo '{"items":[{"kind":"HTTPRoute","metadata":{"name":"other-app","namespace":"other-team"}}]}'
fi
""")
        script = f'source "{ROOT}/stages/stage5/scripts/context.sh"; apollo_context_guard; apollo_assert_exclusive_platform'
        result = subprocess.run(['bash', '-c', script], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('resource outside this snapshot', result.stderr)
        self.assertNotIn('delete', self.calls())

    def test_https_workflow_checks_trust_and_cancels_booking(self):
        self.env['KUBE_CONTEXT'] = 'kind-apollo11'
        self.tool('kubectl', """echo "$*" >> "$CALL_LOG"
if [[ "$*" == *"get service"* ]]; then echo 172.18.0.50; else echo ZmFrZS1jZXJ0; fi
""")
        self.tool('curl', """echo "$*" >> "$CALL_LOG"
url="${@: -1}"
if [[ "$url" == *untrusted.apollo.invalid* ]]; then exit 60; fi
case "$url" in
  */api/users/login) echo '{"token":"fake-test-token"}' ;;
  *flight.apollo.local/api/flights) echo '{"flights":[{"id":"test-flight","status":"SCHEDULED","availableSeats":10,"origin":"BOM","destination":"SIN","departureTime":"2026-10-05T08:00:00Z"}]}' ;;
  *search.apollo.local/api/search*) echo '{"results":[{"id":"test-flight"}],"total":1}' ;;
  */api/bookings) echo '{"id":"test-booking"}' ;;
  */api/bookings/test-booking)
    if [[ "$*" == *"-X DELETE"* ]]; then echo '{"message":"Booking cancelled"}'; else echo '{"status":"CANCELLED"}'; fi ;;
  *) echo '{"status":"ok"}' ;;
esac
""")
        result = self.run_script('stages/stage5/scripts/verify-tls.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('hostname rejection passed', result.stdout)
        self.assertIn('--cacert', self.calls())
        self.assertIn('--resolve identity.apollo.local:443:172.18.0.50', self.calls())
        self.assertIn('-X DELETE', self.calls())
        self.assertNotIn(' -k ', self.calls())

    def test_https_workflow_rejects_an_empty_search_result(self):
        self.env['KUBE_CONTEXT'] = 'kind-apollo11'
        self.tool('kubectl', """if [[ "$*" == *"get service"* ]]; then echo 172.18.0.50; else echo ZmFrZS1jZXJ0; fi
""")
        self.tool('curl', """url="${@: -1}"
if [[ "$url" == *untrusted.apollo.invalid* ]]; then exit 60; fi
case "$url" in
  */api/users/login) echo '{"token":"fake-test-token"}' ;;
  *flight.apollo.local/api/flights) echo '{"flights":[{"id":"test-flight","status":"SCHEDULED","availableSeats":10,"origin":"BOM","destination":"SIN","departureTime":"2026-10-05T08:00:00Z"}]}' ;;
  *search.apollo.local/api/search*) echo '{"results":[],"total":0}' ;;
  *) echo '{"status":"ok"}' ;;
esac
""")
        result = self.run_script('stages/stage5/scripts/verify-tls.sh')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('hostname rejection passed', result.stdout)

    def test_certificate_lookup_failure_never_overwrites_secret(self):
        self.tool('kubectl', 'echo "$*" >> "$CALL_LOG"\nif [[ "$*" == *"get secret"* ]]; then exit 41; fi\n')
        result = self.run_script('stages/stage5/scripts/generate-certs.sh', '--context', 'kind-apollo11')
        self.assertEqual(result.returncode, 41)
        self.assertNotIn('create secret', self.calls())
        self.assertNotIn('apply', self.calls())

    def test_normal_teardown_rejects_foreign_monitoring_before_bundle_deletion(self):
        self.env['KUBE_CONTEXT'] = 'kind-apollo11'
        self.tool('kubectl', """echo "$*" >> "$CALL_LOG"
if [[ "$*" == *"get crd"* ]]; then
  echo prometheuses.monitoring.coreos.com
else
  echo '{"items":[{"kind":"Prometheus","metadata":{"name":"other-metrics","namespace":"other-team"}}]}'
fi
""")
        self.tool('helm', 'echo "HELM $*" >> "$CALL_LOG"; exit 97\n')
        for stage in (6, 7):
            result = self.run_script(f'stages/stage{stage}/scripts/teardown.sh')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('resource outside this snapshot', result.stderr)
        self.assertNotIn('delete', self.calls())
        self.assertNotIn('HELM', self.calls())

    def test_ebs_preview_requires_both_ownership_filters(self):
        self.tool('aws', 'echo "$*" >> "$CALL_LOG"\necho vol-test\n')
        result = self.run_script('stages/eks/scripts/ebs-sweep.sh', 'eu-west-1', 'apollo-test')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Would delete vol-test', result.stdout)
        self.assertIn('tag:kubernetes.io/cluster/apollo-test,Values=owned', self.calls())
        self.assertIn('tag:kubernetes.io/created-for/pvc/namespace', self.calls())
        self.assertNotIn('delete-volume', self.calls())

    def test_ebs_query_failure_does_not_report_success(self):
        self.tool('aws', 'echo "$*" >> "$CALL_LOG"\nexit 42\n')
        result = self.run_script('stages/eks/scripts/ebs-sweep.sh')
        self.assertEqual(result.returncode, 42)
        self.assertNotIn('No unattached', result.stdout)
        self.assertNotIn('delete-volume', self.calls())

    def test_ebs_rechecks_before_deleting(self):
        self.tool('aws', '''echo "$*" >> "$CALL_LOG"
if [[ "$*" == *"--volume-ids"* ]]; then echo ''; else echo vol-test; fi
''')
        result = self.run_script('stages/eks/scripts/ebs-sweep.sh', '--delete')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('refusing deletion', result.stderr)
        self.assertNotIn('delete-volume', self.calls())

    def test_ebs_delete_failure_is_nonzero(self):
        self.tool('aws', '''echo "$*" >> "$CALL_LOG"
if [[ "$*" == *"delete-volume"* ]]; then exit 43; else echo vol-test; fi
''')
        result = self.run_script('stages/eks/scripts/ebs-sweep.sh', '--delete')
        self.assertEqual(result.returncode, 43)
        self.assertNotIn('Deleted vol-test', result.stdout)

    def test_stage1_to_3_scripts_support_help_context_and_reject_foreign_context(self):
        self.tool('kubectl', 'echo "$*" >> "$CALL_LOG"\n')
        for stage in (1, 2, 3):
            for script in ('apply.sh', 'verify.sh', 'teardown.sh'):
                path = f'stages/stage{stage}/scripts/{script}'
                with self.subTest(path=path, mode='help'):
                    self.log.unlink(missing_ok=True)
                    res = self.run_script(path, '--help')
                    self.assertEqual(res.returncode, 0, res.stderr)
                    self.assertEqual(self.calls(), '')
                with self.subTest(path=path, mode='foreign-context'):
                    self.log.unlink(missing_ok=True)
                    res = self.run_script(path, '--context', 'arn:aws:eks:unsafe')
                    self.assertEqual(res.returncode, 2)
                    self.assertIn('Refusing context', res.stderr)
                    self.assertEqual(self.calls(), '')
            for script in ('verify.sh', 'teardown.sh'):
                path = f'stages/stage{stage}/scripts/{script}'
                for args in (('--context', 'kind-apollo11'), ('kind-apollo11',)):
                    with self.subTest(path=path, args=args):
                        self.log.unlink(missing_ok=True)
                        if script == 'teardown.sh':
                            self.tool('kubectl', 'echo "$*" >> "$CALL_LOG"\nif [[ "$*" == *"get namespace"* ]]; then exit 1; fi\n')
                        else:
                            self.tool('curl', 'exit 1\n')
                            self.tool('kubectl', """echo "$*" >> "$CALL_LOG"
case "$*" in
  *"-l app=search"*) echo ErrImagePull ;;
  *"redis-cli"*) exit 1 ;;
esac
""")
                        res = self.run_script(path, *args)
                        self.assertNotIn('Refusing context', res.stderr)
                        self.assertTrue(
                            any(line.startswith('--context kind-apollo11 ') for line in self.calls().splitlines()),
                            f'Expected --context kind-apollo11 in calls for {path} {args}: {self.calls()}'
                        )

    def test_stage2_teardown_deletes_traefik_serviceaccount(self):
        marker = self.work / 'crd-deleted'
        self.tool('kubectl', f"""echo "$*" >> "$CALL_LOG"
case "$*" in
  *"delete customresourcedefinition"*) touch "{marker}" ;;
  *"get crd -o name"*) [[ -f "{marker}" ]] || echo customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io ;;
  *"get namespace"*) exit 1 ;;
esac
""")
        result = self.run_script('stages/stage2/scripts/teardown.sh', '--context', 'kind-apollo11')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('delete serviceaccount traefik -n kube-system', self.calls())

    def test_stage3_verify_fails_survival_when_booking_id_is_empty(self):
        self.tool('kubectl', """echo "$*" >> "$CALL_LOG"
case "$*" in
  *"owning-gateway-name=apollo-gateway"*) echo 172.18.0.50 ;;
  *"redis-cli"*) exit 1 ;;
  *"get secret apollo-tls-secret"*) echo ZmFrZS1jZXJ0 ;;
esac
""")
        self.tool('curl', """url="${@: -1}"
if [[ "$url" == *untrusted.apollo.invalid* ]]; then exit 60; fi
case "$url" in
  */api/users/login) echo '{"token":"fake-token"}' ;;
  */api/flights) echo '{"flights":[{"id":"flight-1","status":"SCHEDULED","availableSeats":10,"origin":"BOM","destination":"SIN","departureTime":"2026-10-05T08:00:00Z"}]}' ;;
  */api/bookings) echo '{"error":"no seats"}' ;;
  *) echo '{"status":"ok"}' ;;
esac
""")
        result = self.run_script('stages/stage3/scripts/verify.sh', '--context', 'kind-apollo11')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Data survival skipped: booking creation failed', result.stdout)
        self.assertNotIn('Data survival proven', result.stdout)

    def test_stage4_to_7_scripts_support_help_and_reject_foreign_context(self):
        self.tool('kubectl', 'echo "$*" >> "$CALL_LOG"\n')
        paths = [
            f'stages/stage{stage}/scripts/{script}'
            for stage in (4, 5, 6, 7)
            for script in ('apply.sh', 'verify.sh', 'teardown.sh')
        ] + [
            f'stages/stage{stage}/argocd/scripts/teardown.sh'
            for stage in (5, 6, 7)
        ]
        for path in paths:
            with self.subTest(path=path, mode='help'):
                self.log.unlink(missing_ok=True)
                res = self.run_script(path, '--help')
                self.assertEqual(res.returncode, 0, res.stderr)
                self.assertEqual(self.calls(), '')
            with self.subTest(path=path, mode='foreign-context'):
                self.log.unlink(missing_ok=True)
                res = self.run_script(path, '--context', 'arn:aws:eks:unsafe')
                self.assertEqual(res.returncode, 2)
                self.assertRegex(res.stderr, r'Refusing .*context')
                self.assertEqual(self.calls(), '')

    def test_stage5_to_7_argocd_full_teardown_refuses_when_application_remains(self):
        self.env['KUBE_CONTEXT'] = 'kind-apollo11'
        self.tool('kubectl', """echo "$*" >> "$CALL_LOG"
case "$*" in
  *"get application "*) exit 1 ;;
  *"get applications.argoproj.io"*) echo application.argoproj.io/other-team-app ;;
esac
""")
        for stage in (5, 6, 7):
            with self.subTest(stage=stage):
                self.log.unlink(missing_ok=True)
                res = self.run_script(f'stages/stage{stage}/argocd/scripts/teardown.sh', '--full')
                self.assertNotEqual(res.returncode, 0)
                self.assertIn('Applications still exist', res.stderr + res.stdout)
                self.assertNotIn('delete appproject', self.calls())
                self.assertNotIn('delete namespace', self.calls())
                self.assertNotIn('delete ns', self.calls())

    def test_stage7_scaling_lab_cleanup_handles_absent_annotations(self):
        self.env['KUBE_CONTEXT'] = 'kind-apollo11'
        self.tool('kubectl', """echo "$*" >> "$CALL_LOG"
case "$*" in
  *"get nodes"*) echo worker-1 ;;
esac
""")
        res = self.run_script('stages/stage7/scripts/scaling-lab.sh', 'cleanup', '--context', 'kind-apollo11')
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertNotIn('patch hpa', self.calls())
        self.assertIn('taint node worker-1', self.calls())


if __name__ == '__main__':
    unittest.main()
