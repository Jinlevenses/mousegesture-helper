from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

forbidden_files = [
    ROOT / 'src' / 'SmoothScroll.c',
    ROOT / 'src' / 'SmoothScroll.h',
    ROOT / 'tests' / 'test_smooth_scroll.c',
]
for path in forbidden_files:
    assert not path.exists(), f'smooth-scroll file still exists: {path.relative_to(ROOT)}'

checks = {
    ROOT / 'src' / 'main.m': [
        'SmoothScroll',
        'kCGEventScrollWheel',
        'kCGScrollWheelEvent',
        'mg_scroll_',
        'post_smooth_scroll',
        'MG_SCROLL_',
    ],
    ROOT / 'scripts' / 'build.sh': ['SmoothScroll'],
    ROOT / 'scripts' / 'com.local.mousegesture-helper.plist.template': ['MG_SCROLL_'],
    ROOT / 'Makefile': ['test_smooth_scroll', 'SmoothScroll'],
}

for path, forbidden_terms in checks.items():
    text = path.read_text()
    for term in forbidden_terms:
        assert term not in text, f'{term!r} still present in {path.relative_to(ROOT)}'

print('smooth-scroll removal checks passed')
