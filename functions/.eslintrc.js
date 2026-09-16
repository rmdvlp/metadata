module.exports = {
  root: true,
  env: {
    es2020: true,
    node: true,
  },
  extends: [
    "eslint:recommended",
    "google",
    "plugin:@typescript-eslint/recommended",
  ],
  parser: "@typescript-eslint/parser",
  parserOptions: {
    project: ["./tsconfig.json"],
    sourceType: "module",
    tsconfigRootDir: __dirname,
  },
  ignorePatterns: [
    "/lib/**/*",
    "/node_modules/**/*",
    ".eslintrc.js",
  ],
  plugins: ["@typescript-eslint", "import"],
  rules: {
    "quotes": ["error", "double", {avoidEscape: true}],
    "import/no-unresolved": "off",
    "indent": ["error", 2, {SwitchCase: 1}],
    "object-curly-spacing": ["error", "never"],
    "max-len": ["error", {code: 120, ignoreUrls: true}],
    "require-jsdoc": "off",
    "valid-jsdoc": "off",
    "camelcase": "off",
    "new-cap": ["error", {capIsNew: false}],
    "@typescript-eslint/no-explicit-any": "off",
    "@typescript-eslint/no-unused-vars": ["error", {argsIgnorePattern: "^_"}],
  },
};
