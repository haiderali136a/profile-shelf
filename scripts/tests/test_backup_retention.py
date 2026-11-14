import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('retention', Path(__file__).resolve().parents[1]/'retain-app-backups.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class RetentionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.current = self.app('Profile Shelf.app')
    def tearDown(self): self.temp.cleanup()
    def app(self, name, identifier=module.BUNDLE_ID):
        path = self.root/name
        (path/'Contents').mkdir(parents=True)
        (path/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':identifier}))
        (path/'Contents/marker').write_text(name)
        return path
    def verify(self, path): return module.owned_app(path) and not (path/'unsigned').exists()
    def run_retention(self): return module.retain(self.current, 'Profile Shelf.backup-', verify=self.verify)
    def test_keeps_newest_verified_backup_and_current(self):
        old = self.app('Profile Shelf.backup-20261101010101.app')
        new = self.app('Profile Shelf.backup-20261102010101.app')
        self.assertEqual(self.run_retention(), [old.name])
        self.assertTrue(new.exists()); self.assertTrue(self.current.exists())
    def test_foreign_unsigned_unrelated_and_account_files_are_untouched(self):
        foreign=self.app('Profile Shelf.backup-20261103010101.app','foreign')
        unsigned=self.app('Profile Shelf.backup-20261104010101.app'); (unsigned/'unsigned').touch()
        unrelated=self.app('Another app.app')
        data=self.root/'auth.json'; data.write_text('preserve account fixture')
        for date in ['20261101010101','20261102010101']: self.app(f'Profile Shelf.backup-{date}.app')
        self.run_retention()
        for path in [foreign,unsigned,unrelated,data]: self.assertTrue(path.exists())
        self.assertEqual(data.read_text(),'preserve account fixture')
    def test_symlink_bundle_is_not_followed(self):
        target=self.app('External.app')
        link=self.root/'Profile Shelf.backup-20261103010101.app'; link.symlink_to(target,target_is_directory=True)
        self.assertFalse(module.owned_app(link))
        self.assertEqual(self.run_retention(),[]); self.assertTrue(target.exists())
    def test_invalid_current_prevents_all_deletion(self):
        old=self.app('Profile Shelf.backup-20261101010101.app')
        (self.current/'unsigned').touch()
        with self.assertRaises(ValueError): self.run_retention()
        self.assertTrue(old.exists())
    def test_failed_retained_backup_recheck_prevents_deletion(self):
        old=self.app('Profile Shelf.backup-20261101010101.app')
        new=self.app('Profile Shelf.backup-20261102010101.app')
        checks={}
        def verify(path):
            checks[path]=checks.get(path,0)+1
            return self.verify(path) and not (path==new and checks[path]>1)
        with self.assertRaises(ValueError): module.retain(self.current,'Profile Shelf.backup-',verify=verify)
        self.assertTrue(old.exists()); self.assertTrue(new.exists())
    def test_no_backup_is_not_an_error(self): self.assertEqual(self.run_retention(),[])
    def test_unexpected_prefix_is_rejected(self):
        with self.assertRaises(ValueError): module.retain(self.current,'',verify=self.verify)
    def test_previous_build_pattern_supports_pid_and_leaves_other_names(self):
        old=self.app('Profile Shelf.previous-20261101010101-12.app')
        latest=self.app('Profile Shelf.previous-20261102010101-99.app')
        malformed=self.app('Profile Shelf.previous-random.app')
        module.retain(self.current,'Profile Shelf.previous-',verify=self.verify)
        self.assertFalse(old.exists()); self.assertTrue(latest.exists()); self.assertTrue(malformed.exists())

class MetadataRetentionTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.root=Path(self.temp.name).resolve()
    def tearDown(self): self.temp.cleanup()
    def fixture(self,name):
        path=self.root/name; path.mkdir(); (path/'preferences.json').write_text('{"profiles":[]}'); return path
    def test_keeps_newest_snapshot_only(self):
        old=self.fixture('20261101010101-1'); new=self.fixture('20261102010101-2')
        self.assertEqual(module.retain_metadata(self.root),[old.name])
        self.assertTrue(new.exists())
    def test_unknown_files_malformed_data_and_account_folders_are_preserved(self):
        old=self.fixture('20261101010101-1'); new=self.fixture('20261102010101-2')
        foreign=self.fixture('20261103010101-3'); (foreign/'auth.json').write_text('preserve')
        broken=self.fixture('20261104010101-4'); (broken/'preferences.json').write_text('invalid')
        account=self.fixture('user-account')
        module.retain_metadata(self.root)
        self.assertFalse(old.exists())
        for path in [new,foreign,broken,account]: self.assertTrue(path.exists())
    def test_linked_preferences_are_not_followed(self):
        outside=self.root/'external.json'; outside.write_text('{"profiles":[]}')
        folder=self.root/'20261101010101-1'; folder.mkdir(); (folder/'preferences.json').symlink_to(outside)
        self.assertEqual(module.retain_metadata(self.root),[])
        self.assertTrue(outside.exists()); self.assertTrue(folder.exists())

if __name__=='__main__': unittest.main(verbosity=2)
