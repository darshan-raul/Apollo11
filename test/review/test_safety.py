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


if __name__ == '__main__':
    unittest.main()
