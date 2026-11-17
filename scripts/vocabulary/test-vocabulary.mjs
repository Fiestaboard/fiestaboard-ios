import assert from 'node:assert/strict';
import {checkSwift} from './check-vocabulary.mjs';
assert.equal(checkSwift('Text("Your hub")', 'App/Test.swift').length, 0);
assert.equal(checkSwift('Text("Server")', 'App/Test.swift').length, 1);
console.log('Vocabulary positive and negative controls passed');
