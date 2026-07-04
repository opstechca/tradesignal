// Self-check for the result % logic used when admin closes a signal.
// Run: node test-pnl.mjs
function pnl(side, entry, exit) {
  let pct = ((exit - entry) / entry) * 100;
  if (side === 'SELL') pct = -pct;
  return Math.round(pct * 100) / 100;
}
const eq = (a, b, m) => { if (a !== b) { console.error(`FAIL ${m}: ${a} !== ${b}`); process.exit(1); } };

// BUY: target above entry = win, SL below = loss
eq(pnl('BUY', 100, 110), 10, 'buy target');
eq(pnl('BUY', 100, 95), -5, 'buy stoploss');
// SELL: price falls to target = win (sold high, bought back low)
eq(pnl('SELL', 100, 90), 10, 'sell target');
eq(pnl('SELL', 100, 105), -5, 'sell stoploss');
console.log('ok: P&L direction correct for BUY and SELL');
