#!/usr/bin/env python3
"""Select ordered observability resources from this stage's rendered YAML.

Uses only the standard library. It reads top-level metadata from manifests
rendered by Helm/Kustomize; it does not rewrite nested YAML or scalar values.
"""
import argparse
import re
import sys


def signal_stage(document):
    match = re.search(r'^metadata:\n((?:[ \t].*\n|\n)*)', document, re.M)
    metadata = match.group(1) if match else ''
    name_match = re.search(r'^  name: ([^\n]+)', metadata, re.M)
    ns_match = re.search(r'^  namespace: ([^\n]+)', metadata, re.M)
    name = name_match.group(1).strip('"\'') if name_match else ''
    namespace = ns_match.group(1).strip('"\'') if ns_match else ''
    if namespace != 'apollo-observability' and name != 'apollo-observability':
        return None
    if name.startswith('grafana'):
        return 2
    if name == 'apollo-services':
        return 3
    if name.startswith(('loki', 'alloy')):
        return 4
    if name.startswith(('tempo', 'otel-collector')):
        return 5
    return 1


def select(text, substage, baseline=False):
    output = []
    for document in re.split(r'^---\s*\n', text, flags=re.M):
        if not document.strip():
            continue
        stage = signal_stage(document)
        if (baseline and stage is None) or (not baseline and stage is not None and stage <= substage):
            output.append(document)
    return '---\n'.join(output)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--substage', type=int, choices=range(1, 7), default=6)
    parser.add_argument('--baseline', action='store_true')
    args = parser.parse_args()
    sys.stdout.write(select(sys.stdin.read(), args.substage, args.baseline))
