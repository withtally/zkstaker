// script/RunScript.js
const { execSync } = require('child_process');

const scriptName = process.argv[2];
if (process.argv.length < 4) {
  console.error("Usage: node RunScript.js <script-name> <network>");
  process.exit(1);
}

const network = process.argv[3];
execSync(`npx hardhat clean && npx hardhat compile && npx hardhat run script/${scriptName} --network ${network}`, { stdio: 'inherit' });
