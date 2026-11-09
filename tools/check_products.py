"""Refuse a firmware library that does not match PRODUCTS.md.

    python tools/check_products.py <flasher repo>

Reads the flasher's COMMITTED firmware/library.json (what make_firmware_bundle.py packs) and checks:
  - every "[HSI BUILDS] <name> <board>, built ... from <commit>" entry has its name + board in the
    Products table, and its firmware.bin's HSI-OTA1 product id is the registered one (or its legacy code);
  - every other entry is listed by name under "Hand-made entries".
Exit 1 with the list of problems, else 0.
"""
import json, os, re, struct, subprocess, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def cells(line):
    return [c.strip().strip('`') for c in line.strip().strip('|').split('|')]


def registry():
    products, hand, section = {}, set(), None
    for line in open(os.path.join(HERE, 'PRODUCTS.md'), encoding='utf-8'):
        if line.startswith('## '):
            section = line[3:].strip()
            continue
        if not line.startswith('|') or set(line.strip()) <= set('|-: '):
            continue
        c = cells(line)
        if section == 'Products' and c[0] != 'Builds name':
            ids = {int(x, 16) if x.startswith('0x') else int(x) for x in (c[2], c[3]) if x != '-'}
            for board in (b.strip() for b in c[1].split(',')):
                products[(c[0], board)] = ids
        elif section == 'Hand-made entries' and c[0] != 'Entry name':
            hand.add(c[0])
    return products, hand


def git_show(repo, path):
    return subprocess.run(['git', '-C', repo, 'show', os.environ.get('HSI_LIB_REF', 'HEAD') + ':' + path], capture_output=True, check=True).stdout


def main(repo):
    products, hand = registry()
    lib = json.loads(git_show(repo, 'firmware/library.json').decode('utf-8'))
    entries = lib['entries'] if isinstance(lib, dict) else lib
    bad = []
    for e in entries:
        name, notes = e.get('name', ''), e.get('notes', '')
        m = re.match(r'\[HSI BUILDS\] (\S+) (\S+), built .+? from [0-9a-f]{7,}', notes)
        if not m:
            if notes.startswith('[HSI BUILDS]'):
                bad.append('%s: notes must read "[HSI BUILDS] <name> <board>, built <when> from <commit>."' % name)
            elif name not in hand:
                bad.append('%s: hand-made entry not listed under "Hand-made entries" in PRODUCTS.md' % name)
            continue
        key = (m.group(1), m.group(2))
        if key not in products:
            bad.append('%s: "%s %s" is not in the Products table of PRODUCTS.md' % (name, *key))
            continue
        ids = products[key]
        app = next((p['file'] for p in e.get('parts', []) if p.get('role') in ('app', 'firmware') or p.get('file') == 'firmware.bin'), None)
        if not ids or not app:
            continue
        try:
            img = git_show(repo, 'firmware/%s/%s' % (e['folder'], app))
        except subprocess.CalledProcessError:
            bad.append('%s: %s is not committed' % (name, app))
            continue
        t = img[-32:]
        if t[:8] != b'HSI-OTA1':
            bad.append('%s: %s has no HSI-OTA1 stamp (product %s expects one)' % (name, app, '/'.join(hex(i) for i in ids)))
        elif struct.unpack('<H', t[8:10])[0] not in ids:
            bad.append('%s: %s is stamped 0x%04x, PRODUCTS.md says %s' % (name, app, struct.unpack('<H', t[8:10])[0],
                                                                          '/'.join('0x%04x' % i for i in ids)))
    if bad:
        print('PRODUCTS.md check FAILED - fix the library entry or add the product to PRODUCTS.md first:')
        print('\n'.join('  - ' + b for b in bad))
        return 1
    print('PRODUCTS.md check OK: %d library entries' % len(entries))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else r'E:\HSI-Firmware-Flasher'))
