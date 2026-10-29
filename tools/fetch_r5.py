"""Download the r5 candidate models (guns, first-person arms) from the Objaverse mirror of Sketchfab.

    python -I tools/fetch_r5.py [name ...]

Uses fetch_assets.sketchfab (licence checked against the Sketchfab API: CC-BY or CC0 only). The same entries are
listed in tools/asset_sources.json under "sketchfab".
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fetch_assets  # noqa: E402

CANDIDATES = {
    # first-person arms
    'arms_fischer': ('547a45535f0c4fe787948f7a7a6a88db', 'first-person arms (rigged hands)'),
    'arms_goldgryphon': ('50898e9112c54ff38fcdfb0827b27397', 'first-person arms'),
    'arms_bumstrum': ('e3c42c05b22944e5839deb8e003f0987', 'first-person arms'),
    'arms_aerolab': ('c29feda751284a32b575486f53c49180', 'first-person arms'),
    # guns
    'pistol_m9': ('348015284eca46fe8e1822508381dfd8', '9 mm service pistol (P92)'),
    'pistol_92fs': ('e529e0dc704f4f7fb47d632ac9aa7f1e', '9 mm service pistol (P92, alternative)'),
    'pistol_92_dunlop': ('b2bcc5b626524e38a88dff56eeea980e', '9 mm service pistol (P92, alternative)'),
    'shotgun_ou_toz34': ('2f61e00bf02849688891ec0a1c9c5fef', 'over-under shotgun (S686)'),
    'shotgun_db_pepego': ('04741a40f2224cffafc343b0236d5bbe', 'double-barrel shotgun (S686 alternative)'),
    'shotgun_db_schris': ('1e03c51ebc454aeba36ba1c575cff067', 'double-barrel shotgun (S686 alternative)'),
    'rifle_fal': ('7f548d1f79f7418fad852f3d7293ec2c', '7.62 battle rifle (SLR)'),
    'rifle_l1a1': ('deb5b8041100481c93701269ee76bb92', '7.62 battle rifle (SLR, alternative)'),
    'smg_microuzi': ('b63e34393404494b9463db6111932961', 'machine pistol (Micro UZI)'),
    'smg_microuzi_b': ('37eb29034d5442d5979a66ce9904962b', 'machine pistol (Micro UZI, alternative)'),
    'smg_thompson': ('5fe11dfebf734b4aa49c43545397abd1', 'Thompson submachine gun'),
    'smg_thompson_b': ('b43073761c44464eb90f9b981f7284fe', 'Thompson submachine gun (alternative)'),
    'bolt_m24': ('da99b3c489d3445da576b0b94c62b310', 'M24 bolt-action rifle'),
    'bolt_m24_b': ('561e3726a95b43f7947b0d90ffd502a0', 'M24 bolt-action rifle (alternative)'),
    'bolt_r700': ('7705ea5b53384404ae0316ce20838f0b', 'M24 bolt-action rifle (Remington 700, alternative)'),
    'revolver_nagant': ('d8ce5431c53c4f32af9c82fbd2ffeac6', 'R1895 revolver'),
    'revolver_nagant_b': ('308ec7e09b49424a9abd72fad7c26b4e', 'R1895 revolver (alternative)'),
    'shotgun_pipe': ('f0151ad09d414d1b8b8466bae9d38b56', 'improvised pipe shotgun (sumpak)'),
    'shotgun_pipe_ph': ('452a7f15fbd642c5be6f85a23a327338', 'Philippine guerrilla gun (sumpak, alternative)'),
    'rifle_beryl_tt': ('bdec2c46a8c24981bb7dbe7ef6484c1b', 'Beryl M762 assault rifle'),
    'rifle_ak103': ('21b2e86d257246639ce187b904d124c8', 'Beryl M762 assault rifle (AK-103 alternative)'),
    'shotgun_pipe_bosnian': ('814ebc4320e145d7bb26b7972be0a633', 'improvised shotgun (sumpak, alternative)'),
}


def main():
    names = sys.argv[1:] or list(CANDIDATES)
    for n in names:
        uid, purpose = CANDIDATES[n]
        try:
            print(n, fetch_assets.sketchfab(n, uid, purpose), flush=True)
        except Exception as e:  # keep going: one refused licence or missing mirror copy must not stop the rest
            print(n, 'FAILED', e, flush=True)


if __name__ == '__main__':
    main()
