#!/usr/bin/env python3
"""Reject destructive or foreign-namespace saved plans before deployment."""
import json
import sys


def validate(plan):
    if plan.get('metadata', {}).get('mode') != 'apply':
        raise ValueError('Only additive apply-mode plans may be deployed')
    changes = plan['changes']
    if not isinstance(changes, list):
        raise ValueError('Plan changes must be an array')
    for change in changes:
        if change.get('action') not in {'CREATE', 'UPDATE'}:
            raise ValueError('Only CREATE and UPDATE actions are allowed')
        if change.get('namespace') != 'summit-ai-demo':
            raise ValueError('Plan changes must belong to summit-ai-demo')
    if plan['summary']['total_changes'] != len(changes):
        raise ValueError('Plan summary does not match its changes')


if __name__ == '__main__':
    with open(sys.argv[1]) as source:
        validate(json.load(source))
    print('Validated additive summit-ai-demo plan.')
