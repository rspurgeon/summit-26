import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('check_plan', Path(__file__).with_name('check-plan.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PlanValidationTest(unittest.TestCase):
    def setUp(self):
        self.plan = {
            'metadata': {'mode': 'apply'},
            'changes': [{'action': 'UPDATE', 'namespace': 'summit-ai-demo'}],
            'summary': {'total_changes': 1},
        }

    def test_additive_and_empty_plans(self):
        module.validate(self.plan)
        module.validate({'metadata': {'mode': 'apply'}, 'changes': [], 'summary': {'total_changes': 0}})

    def test_reject_wrong_mode_destructive_and_foreign_changes(self):
        for field, value in [('mode', 'sync'), ('action', 'DELETE'), ('namespace', 'other')]:
            with self.subTest(field=field):
                plan = copy.deepcopy(self.plan)
                target = plan['metadata'] if field == 'mode' else plan['changes'][0]
                target[field] = value
                with self.assertRaises(ValueError):
                    module.validate(plan)

    def test_reject_inconsistent_summary(self):
        self.plan['summary']['total_changes'] = 0
        with self.assertRaises(ValueError):
            module.validate(self.plan)
