#!/usr/bin/env python3
"""Regenerate Stage 5/6/7 derived manifests; --check fails on chart drift."""
import argparse
import json
from pathlib import Path
import subprocess
import yaml

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
repo = Path(__file__).resolve().parent.parent
for stage in (5, 6, 7):
    root = repo / f'stages/stage{stage}'
    command = ['helm', 'template', 'apollo11', str(root / 'helm/apollo11'),
               '--namespace', 'apollo-airlines-apps',
               '--set', 'gateway.envoy.bundleInstall=false',
               '--set', 'metallb.bundleInstall=false', '--set', 'pdb.enabled=false']
    if stage == 5:
        command.append('--skip-tests')
    if stage == 7:
        command += ['--set', 'autoscaling.metricsServer.bundleInstall=false',
                    '--set', 'vpa.bundleInstall=false']
    rendered = subprocess.check_output(command, text=True)
    base = root / 'overlays/base/generated.yaml'
    header_lines = []
    for line in base.read_text().splitlines()[:3]:
        if line.startswith('#'):
            header_lines.append(line)
        else:
            break
    header = ('\n'.join(header_lines) + '\n') if header_lines else ''
    plain = header + '\n'.join(line.rstrip() for line in rendered.splitlines()) + '\n'
    targets = [(base, plain)]
    if stage in (6, 7):
        # The shared Argo CD platform serves three tenants, so its internal probe
        # checks each tenant's frontend instead of the single-tenant default.
        tenants = [f'http://frontend.apollo-airlines-{env}-ui.svc:3000/healthz'
                   for env in ('dev', 'staging', 'prod')]
        shared_render = subprocess.check_output(
            command + [
                '--set-json', f'observability.blackbox.internalTargets={json.dumps(tenants)}',
                '--set', 'observability.grafana.gatewayNamespace=apollo-airlines-dev-apps',
            ],
            text=True)
        docs = [d for d in yaml.safe_load_all(shared_render) if d and
                d.get('metadata', {}).get('namespace') == 'apollo-observability']
        shared = (f'# Generated from Stage {stage} Helm observability templates; namespaced resources only.\n'
                  + yaml.safe_dump_all(docs, sort_keys=False))
        targets.append((root / 'argocd/platform/observability/generated.yaml', shared))
    for path, content in targets:
        if args.check:
            if path.read_text() != content:
                raise SystemExit(f'{path.relative_to(repo)} is stale; run python3 test/generated.py')
        else:
            path.write_text(content)
