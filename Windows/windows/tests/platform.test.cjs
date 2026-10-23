const {test} = require('node:test');
const assert = require('node:assert/strict');
const {placeIsland} = require('../src/core/platform.cjs');
test('island follows screen top rather than taskbar work area', () => {
  assert.deepEqual(placeIsland({bounds:{x:0,y:0,width:1920,height:1080},workArea:{x:0,y:48,width:1920,height:1032}},680,400), {x:620,y:0,width:680,height:400});
});
test('secondary screen uses its own negative origin', () => {
  assert.deepEqual(placeIsland({bounds:{x:-1920,y:-240,width:1920,height:1080}},680,400), {x:-1300,y:-240,width:680,height:400});
});
