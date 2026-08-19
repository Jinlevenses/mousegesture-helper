import json
from pathlib import Path

path = Path('karabiner/button3-to-f20.json')
data = json.loads(path.read_text())
assert data['title'] == 'MouseGesture Helper'
rules = data['rules']
assert len(rules) == 1
manips = rules[0]['manipulators']
assert len(manips) == 1
m = manips[0]
assert m['type'] == 'basic'
assert m['from']['pointing_button'] == 'button3'
assert m['from']['modifiers']['optional'] == ['any']
assert m['to'] == [{'key_code': 'f20'}], 'F20 must stay down until physical button3 release; do not set repeat:false'
text = path.read_text()
assert 'button4' not in text and 'button5' not in text
print('karabiner config checks passed')
