#!/usr/bin/env python3
"""Regenerate Stage 6/7 derived manifests; --check fails on chart drift."""
import argparse
import json
from pathlib import Path
import subprocess
import yaml

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
repo = Path(__file__).resolve().parent.parent
for stage in (6, 7):
    root = repo / f'stages/stage{stage}'
    command = ['helm', 'template', 'apollo11', str(root / 'helm/apollo11'),
               '--namespace', 'apollo-airlines-apps',
               '--set', 'gateway.envoy.bundleInstall=false',
               '--set', 'metallb.bundleInstall=false', '--set', 'pdb.enabled=false']
    if stage == 7:
        command += ['--set', 'autoscaling.metricsServer.bundleInstall=false',
                    '--set', 'vpa.bundleInstall=false']
    rendered = subprocess.check_output(command, text=True)
    # The shared Argo CD platform serves three tenants, so its internal probe
    # checks each tenant's frontend instead of the single-tenant default.
    tenants = [f'http://frontend.apollo-airlines-{env}-ui.svc:3000/healthz'
               for env in ('dev', 'staging', 'prod')]
    shared_render = subprocess.check_output(
        command + ['--set-json', f'observability.blackbox.internalTargets={json.dumps(tenants)}'],
        text=True)
    base = root / 'overlays/base/generated.yaml'
    header = '\n'.join(base.read_text().splitlines()[:3]) + '\n'
    plain = header + '\n'.join(line.rstrip() for line in rendered.splitlines()) + '\n'
    docs = [d for d in yaml.safe_load_all(shared_render) if d and
            d.get('metadata', {}).get('namespace') == 'apollo-observability']
    shared = (f'# Generated from Stage {stage} Helm observability templates; namespaced resources only.\n'
              + yaml.safe_dump_all(docs, sort_keys=False))
    for path, content in ((base, plain), (root / 'argocd/platform/observability/generated.yaml', shared)):
        if args.check:
            if path.read_text() != content:
                raise SystemExit(f'{path.relative_to(repo)} is stale; run python3 test/generated.py')
        else:
            path.write_text(content)
