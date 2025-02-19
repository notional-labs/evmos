#!/bin/bash
KEYS[0]="dev0"
KEYS[1]="dev1"
KEYS[2]="dev2"
CHAINID="evmos_9000-1"
MONIKER="localtestnet"
KEYRING="test" # remember to change to other types of keyring like 'file' in-case exposing to outside world, otherwise your balance will be wiped quickly. The keyring test does not require private key to steal tokens from you
KEYALGO="eth_secp256k1"
LOGLEVEL="info"
# Set dedicated home directory for the evmosd instance
HOMEDIR="$HOME/.tmp-evmosd"
# to trace evm
#TRACE="--trace"
TRACE=""

# Path variables
CONFIG=$HOMEDIR/config/config.toml
GENESIS=$HOMEDIR/config/genesis.json
TMP_GENESIS=$HOMEDIR/config/tmp_genesis.json

# validate dependencies are installed
command -v jq > /dev/null 2>&1 || { echo >&2 "jq not installed. More info: https://stedolan.github.io/jq/download/"; exit 1; }

# used to exit on first error (any non-zero exit code)
set -e

# Reinstall daemon
make install

# Set client config
evmosd config keyring-backend $KEYRING --home $HOMEDIR
evmosd config chain-id $CHAINID --home $HOMEDIR

# If keys exist they should be deleted
for KEY in "${KEYS[@]}"
do
  evmosd keys add $KEY --keyring-backend $KEYRING --algo $KEYALGO --home $HOMEDIR
done

# Set moniker and chain-id for Evmos (Moniker can be anything, chain-id must be an integer)
evmosd init $MONIKER -o --chain-id $CHAINID --home $HOMEDIR

# Change parameter token denominations to aevmos
cat $GENESIS | jq '.app_state["staking"]["params"]["bond_denom"]="aevmos"' > $TMP_GENESIS && mv $TMP_GENESIS $GENESIS
cat $GENESIS | jq '.app_state["crisis"]["constant_fee"]["denom"]="aevmos"' > $TMP_GENESIS && mv $TMP_GENESIS $GENESIS
cat $GENESIS | jq '.app_state["gov"]["deposit_params"]["min_deposit"][0]["denom"]="aevmos"' > $TMP_GENESIS && mv $TMP_GENESIS $GENESIS
cat $GENESIS | jq '.app_state["evm"]["params"]["evm_denom"]="aevmos"' > $TMP_GENESIS && mv $TMP_GENESIS $GENESIS
cat $GENESIS | jq '.app_state["inflation"]["params"]["mint_denom"]="aevmos"' > $TMP_GENESIS && mv $TMP_GENESIS $GENESIS

# Set gas limit in genesis
cat $GENESIS | jq '.consensus_params["block"]["max_gas"]="10000000"' > $TMP_GENESIS && mv $TMP_GENESIS $GENESIS

# Set claims start time
current_date=$(date -u +"%Y-%m-%dT%TZ")
cat $GENESIS | jq -r --arg current_date "$current_date" '.app_state["claims"]["params"]["airdrop_start_time"]=$current_date' > $TMP_GENESIS && mv $TMP_GENESIS $GENESIS

# Set claims records for validator account
amount_to_claim=10000
claims_key=${KEYS[0]}
node_address=$(evmosd keys show $claims_key --keyring-backend $KEYRING --home $HOMEDIR | grep "address" | cut -c12-)
cat $GENESIS | jq -r --arg node_address "$node_address" --arg amount_to_claim "$amount_to_claim" '.app_state["claims"]["claims_records"]=[{"initial_claimable_amount":$amount_to_claim, "actions_completed":[false, false, false, false],"address":$node_address}]' > $TMP_GENESIS && mv $TMP_GENESIS $GENESIS

# Set claims decay
cat $GENESIS | jq '.app_state["claims"]["params"]["duration_of_decay"]="1000000s"' > $TMP_GENESIS && mv $TMP_GENESIS $GENESIS
cat $GENESIS | jq '.app_state["claims"]["params"]["duration_until_decay"]="100000s"' > $TMP_GENESIS && mv $TMP_GENESIS $GENESIS

# Claim module account:
# 0xA61808Fe40fEb8B3433778BBC2ecECCAA47c8c47 || evmos15cvq3ljql6utxseh0zau9m8ve2j8erz89m5wkz
cat $GENESIS | jq -r --arg amount_to_claim "$amount_to_claim" '.app_state["bank"]["balances"] += [{"address":"evmos15cvq3ljql6utxseh0zau9m8ve2j8erz89m5wkz","coins":[{"denom":"aevmos", "amount":$amount_to_claim}]}]' > $TMP_GENESIS && mv $TMP_GENESIS $GENESIS

# disable produce empty block
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' 's/create_empty_blocks = true/create_empty_blocks = false/g' $CONFIG
  else
    sed -i 's/create_empty_blocks = true/create_empty_blocks = false/g' $CONFIG
fi

if [[ $1 == "pending" ]]; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' 's/create_empty_blocks_interval = "0s"/create_empty_blocks_interval = "30s"/g' $CONFIG
      sed -i '' 's/timeout_propose = "3s"/timeout_propose = "30s"/g' $CONFIG
      sed -i '' 's/timeout_propose_delta = "500ms"/timeout_propose_delta = "5s"/g' $CONFIG
      sed -i '' 's/timeout_prevote = "1s"/timeout_prevote = "10s"/g' $CONFIG
      sed -i '' 's/timeout_prevote_delta = "500ms"/timeout_prevote_delta = "5s"/g' $CONFIG
      sed -i '' 's/timeout_precommit = "1s"/timeout_precommit = "10s"/g' $CONFIG
      sed -i '' 's/timeout_precommit_delta = "500ms"/timeout_precommit_delta = "5s"/g' $CONFIG
      sed -i '' 's/timeout_commit = "5s"/timeout_commit = "150s"/g' $CONFIG
      sed -i '' 's/timeout_broadcast_tx_commit = "10s"/timeout_broadcast_tx_commit = "150s"/g' $CONFIG
  else
      sed -i 's/create_empty_blocks_interval = "0s"/create_empty_blocks_interval = "30s"/g' $CONFIG
      sed -i 's/timeout_propose = "3s"/timeout_propose = "30s"/g' $CONFIG
      sed -i 's/timeout_propose_delta = "500ms"/timeout_propose_delta = "5s"/g' $CONFIG
      sed -i 's/timeout_prevote = "1s"/timeout_prevote = "10s"/g' $CONFIG
      sed -i 's/timeout_prevote_delta = "500ms"/timeout_prevote_delta = "5s"/g' $CONFIG
      sed -i 's/timeout_precommit = "1s"/timeout_precommit = "10s"/g' $CONFIG
      sed -i 's/timeout_precommit_delta = "500ms"/timeout_precommit_delta = "5s"/g' $CONFIG
      sed -i 's/timeout_commit = "5s"/timeout_commit = "150s"/g' $CONFIG
      sed -i 's/timeout_broadcast_tx_commit = "10s"/timeout_broadcast_tx_commit = "150s"/g' $CONFIG
  fi
fi

# Allocate genesis accounts (cosmos formatted addresses)
for KEY in "${KEYS[@]}"
do
  evmosd add-genesis-account $KEY 100000000000000000000000000aevmos --keyring-backend $KEYRING --home $HOMEDIR
done 

# Update total supply with claim values
validators_supply=$(cat $GENESIS | jq -r '.app_state["bank"]["supply"][0]["amount"]')
# Bc is required to add these big numbers
total_supply=$(echo "${#KEYS[@]} * 100000000000000000000000000 + $amount_to_claim" | bc)
cat $GENESIS | jq -r --arg total_supply "$total_supply" '.app_state["bank"]["supply"][0]["amount"]=$total_supply' > $TMP_GENESIS && mv $TMP_GENESIS $GENESIS

# Remove genesis transaction if it exists already
rm -rf $HOMEDIR/config/gentx

# Sign genesis transaction
evmosd gentx ${KEYS[0]} 1000000000000000000000aevmos --keyring-backend $KEYRING --chain-id $CHAINID --home $HOMEDIR
## In case you want to create multiple validators at genesis
## 1. Back to `evmosd keys add` step, init more keys
## 2. Back to `evmosd add-genesis-account` step, add balance for those
## 3. Clone this ~/.evmosd home directory into some others, let's say `~/.clonedEvmosd`
## 4. Run `gentx` in each of those folders
## 5. Copy the `gentx-*` folders under `~/.clonedEvmosd/config/gentx/` folders into the original `~/.evmosd/config/gentx`

# Collect genesis tx
evmosd collect-gentxs --home $HOMEDIR

# Run this to ensure everything worked and that the genesis file is setup correctly
evmosd validate-genesis --home $HOMEDIR

if [[ $1 == "pending" ]]; then
  echo "pending mode is on, please wait for the first block committed."
fi

# Start the node (remove the --pruning=nothing flag if historical queries are not needed)
evmosd start --pruning=nothing $TRACE --log_level $LOGLEVEL --minimum-gas-prices=0.0001aevmos --json-rpc.api eth,txpool,personal,net,debug,web3 --home $HOMEDIR
