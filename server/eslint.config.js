// ESLint (flat config) - server/ (Node ESM).
//
// Amac: calisma zamaninda ReferenceError'a donusecek hatalari (tanimsiz
// degisken / eksik import) derleme zamaninda yakalamak. `no-undef` bu yuzden
// ERROR; kullanilmayan degisken/parametre yalnizca UYARI.
//
// Calistirma:
//   npm run lint        -> yalnizca src/ (CI bunu calistirir)
//   npm run lint:all    -> src + scripts + test + yapilandirma dosyalari
import js from '@eslint/js';
import globals from 'globals';

export default [
  {
    ignores: [
      'node_modules/**',
      'firmware/**',
      'public/**',
      'data/**',
      'coverage/**',
    ],
  },

  js.configs.recommended,

  {
    // Kodda "eslint-disable no-console" yorumlari var; no-console kurali acik
    // olmadigindan bunlar "kullanilmayan direktif" uyarisi uretir -> sustur.
    linterOptions: { reportUnusedDisableDirectives: 'off' },
  },

  {
    files: ['**/*.js', '**/*.mjs'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: {
        ...globals.node,
      },
    },
    rules: {
      // Asil hedef: eksik import / tanimsiz degisken
      'no-undef': 'error',

      // Kullanilmayan degisken: uyari. "_" ile baslayanlar bilerek kullanilmayanlardir.
      'no-unused-vars': [
        'warn',
        {
          args: 'after-used',
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          caughtErrors: 'all',
          caughtErrorsIgnorePattern: '^_',
          ignoreRestSiblings: true,
        },
      ],

      // Mevcut kod tabaninda yaygin kaliplar: hata olarak degil uyari
      'no-empty': ['warn', { allowEmptyCatch: true }],
      'no-useless-escape': 'warn',
      'no-control-regex': 'warn',
      'no-prototype-builtins': 'warn',
      'no-useless-assignment': 'warn',
      'preserve-caught-error': 'off',
      'no-case-declarations': 'warn',
      'no-fallthrough': 'warn',
    },
  },

  // PM2 ecosystem dosyasi CommonJS (.cjs)
  {
    files: ['**/*.cjs'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'commonjs',
      globals: {
        ...globals.node,
        ...globals.commonjs,
      },
    },
  },
];
