"""Seeds, snapshots and compares a Boaz library for the upgrade acceptance run. The app must not be running.

  library.py seed <boaz.sqlite>                  adds fixture folders, tabs, archive and history rows
  library.py snapshot <boaz.sqlite> <out.json>   the rows that must survive an upgrade
  library.py compare <before.json> <after.json>  exits 1 when any of them changed or disappeared
"""
import json
import sqlite3
import sys

# Columns that must come through an upgrade unchanged, per table (GRDB's own columns may be added to, never lost).
KEPT = {
    'profile': ['name', 'dataStoreID', 'isDefault'],
    'space': ['title', 'profileID'],
    'sidebarItem': ['spaceID', 'profileID', 'parentID', 'kind', 'containerKind', 'title', 'url'],
    'archiveItem': ['profileID', 'title', 'url'],
    'historyVisit': ['profileID', 'url', 'title'],
}
NOW = "strftime('%Y-%m-%d %H:%M:%f', 'now')"


def seed(path):
    db = sqlite3.connect(path)
    profile, space = db.execute(
        'SELECT space.profileID, space.id FROM space WHERE deletedAt IS NULL ORDER BY position LIMIT 1').fetchone()
    containers = dict(db.execute(
        "SELECT containerKind, id FROM sidebarItem WHERE kind = 'container' AND spaceID = ? AND deletedAt IS NULL",
        (space,)).fetchall())
    pinned, today = containers.get('pinned'), containers.get('unpinned')
    if not pinned or not today:
        sys.exit(f'Fixture space {space} has no pinned or Today container: {containers}')

    def item(id, parent, kind, title, url, position):
        db.execute('INSERT INTO sidebarItem (id, spaceID, profileID, parentID, kind, title, url, isUnread, '
                   f'isExpanded, position, createdAt, modifiedAt) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, ?, {NOW}, {NOW})',
                   (id, space, profile, parent, kind, title, url, position))

    base = 'http://127.0.0.1:8765'
    item('A0000000-0000-4000-8000-000000000001', pinned, 'folder', 'Fixture folder', None, 900)
    item('A0000000-0000-4000-8000-000000000002', 'A0000000-0000-4000-8000-000000000001', 'tab', 'Pinned fixture',
         f'{base}/pinned', 1)
    item('A0000000-0000-4000-8000-000000000003', 'A0000000-0000-4000-8000-000000000001', 'folder', 'Nested folder',
         None, 2)
    item('A0000000-0000-4000-8000-000000000004', 'A0000000-0000-4000-8000-000000000003', 'tab', 'Nested fixture',
         f'{base}/nested', 1)
    item('A0000000-0000-4000-8000-000000000005', today, 'tab', 'Today fixture', f'{base}/today', -900)
    for n in range(1, 6):
        db.execute('INSERT INTO archiveItem (id, profileID, spaceID, title, url, archivedAt, reason, modifiedAt) '
                   f"VALUES (?, ?, ?, ?, ?, {NOW}, 'closed', {NOW})",
                   (f'B0000000-0000-4000-8000-00000000000{n}', profile, space, f'Archived {n}', f'{base}/archived/{n}'))
        db.execute(f'INSERT INTO historyVisit (id, profileID, url, title, visitedAt) VALUES (?, ?, ?, ?, {NOW})',
                   (f'C0000000-0000-4000-8000-00000000000{n}', profile, f'{base}/visited/{n}', f'Visited {n}'))
    db.commit()


def snapshot(path, out):
    db = sqlite3.connect(path)
    db.row_factory = sqlite3.Row
    rows = {}
    for table, columns in KEPT.items():
        rows[table] = {}
        for row in db.execute(f'SELECT * FROM {table}'):
            rows[table][row['id']] = {key: (row[key].hex() if isinstance(row[key], bytes) else row[key])
                                      for key in ['deletedAt', *columns] if key in row.keys()}
    json.dump(rows, open(out, 'w'), indent=1, sort_keys=True)


def compare(before_path, after_path):
    before, after = json.load(open(before_path)), json.load(open(after_path))
    problems = []
    for table, rows in before.items():
        for id, row in rows.items():
            now = after.get(table, {}).get(id)
            if now is None:
                problems.append(f'{table} {id} is gone')
            elif row.get('deletedAt') is None and now.get('deletedAt') is not None:
                problems.append(f'{table} {id} was deleted')
            else:
                changed = [key for key in KEPT[table] if row.get(key) != now.get(key)]
                if changed:
                    problems.append(f'{table} {id} changed {changed}: {[row.get(k) for k in changed]} -> '
                                    f'{[now.get(k) for k in changed]}')
        print(f'{table}: {len(rows)} before, {len(after.get(table, {}))} after')
    for problem in problems:
        print('FAIL', problem)
    sys.exit(1 if problems else 0)


if __name__ == '__main__':
    command, *arguments = sys.argv[1:]
    {'seed': seed, 'snapshot': snapshot, 'compare': compare}[command](*arguments)
