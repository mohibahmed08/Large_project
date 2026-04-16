import {
  buildThemePackId,
  buildThemeShareTargets,
  extractSharedThemeValue,
  mergeThemePacks,
} from '../themeSharing';

describe('theme sharing helpers', () => {
  test('extractSharedThemeValue accepts raw codes and shared URLs', () => {
    expect(extractSharedThemeValue('ABC123')).toBe('ABC123');
    expect(extractSharedThemeValue('https://calendarplusplus.xyz/?theme=mountain_theme')).toBe('mountain_theme');
  });

  test('mergeThemePacks prefers the latest matching shared theme payload', () => {
    const merged = mergeThemePacks(
      [{ id: 'local-1', name: 'Local theme' }],
      [{ id: 'shared-1', sharedThemeId: 'theme-1', name: 'Server theme' }],
      [{ id: 'shared-1', sharedThemeId: 'theme-1', name: 'Updated server theme' }],
    );

    expect(merged).toEqual([
      { id: 'local-1', name: 'Local theme' },
      { id: 'shared-1', sharedThemeId: 'theme-1', name: 'Updated server theme' },
    ]);
  });

  test('buildThemeShareTargets includes the share code in the text payload', () => {
    const targets = buildThemeShareTargets({
      name: 'Mountain Glow',
      shareCode: 'A1B2C3',
      shareUrl: 'https://calendarplusplus.xyz/?theme=mountain_theme',
    });

    expect(targets.shareText).toContain('Mountain Glow');
    expect(targets.shareText).toContain('A1B2C3');
    expect(targets.shareText).toContain('https://calendarplusplus.xyz/?theme=mountain_theme');
  });

  test('buildThemePackId creates a stable user-prefixed id format', () => {
    expect(buildThemePackId('Mountain Theme')).toMatch(/^user-mountain-theme-\d+$/);
  });
});
