# onchain NFT Market

Simple Starknet onchain Market

### Environment Configuration

```bash
# Set the StarkNet network to mainnet
export STARKNET_NETWORK="mainnet"

# Starkli commands
starkli
starkli account oz init ./account
starkli account deploy ./account

# Set StarkNet RPC for mainnet and goerli
export STARKNET_RPC="https://starknet-mainnet.g.alchemy.com/v2/G9wJH34O_F038b_k329lcjOd_o38JA3j"
export STARKNET_RPC="https://starknet-goerli.g.alchemy.com/v2/-RHvatMphky_TLyhARL-4imNkCmPqQgS"

# Set the keystore path
export STARKNET_KEYSTORE=/Users/os/Documents/code/biblio/onchain-nft-market/keys

# Declare and deploy contracts
starkli declare /Users/os/Documents/code/biblio/onchain-nft-market/target/dev/marketplace_Market.contract_class.json --account ./account
starkli deploy 0x04624b17451699a93ea17a444ee8503a6d9317c1f8eb7fc4d27269d1a46b1cc3 $LORDS_ADDRESS 300 $DAO_ADDRESS --account ./account
```

### Configuration for Goerli and Mainnet

```bash
# Goerli
export LORDS_ADDRESS=0x05e367ac160e5f90c5775089b582dfc987dd148a5a2f977c49def2a6644f724b
export BEASTS_ADDRESS=0x05c909139dbef784180eef8ce7a2f5bf52afe567aa73aaa77b8d8243ad5b6b96
export GOLDEN_TOKEN_ADDRESS=0x003583470A8943479F8609192Da4427caC45BdF66a58C84043c7Ab2FC722C0C0
export DAO_ADDRESS=0x45419c8e879021144134bf9cafe8071f3666d1ce8968551e739df2ee8b38db1

# Mainnet
export LORDS_ADDRESS=0x0124aeb495b947201f5fac96fd1138e326ad86195b98df6dec9009158a533b49
export BEASTS_ADDRESS=0x0158160018d590d93528995b340260e65aedd76d28a686e9daa5c4e8fad0c5dd
export GOLDEN_TOKEN_ADDRESS=0x04f5e296c805126637552cf3930e857f380e7c078e8f00696de4fc8545356b1d
export ARCADE_ACCOUNT_CLASS_HASH=0x0251830adc3d8b4d818c2c309d71f1958308e8c745212480c26e01120c69ee49
export DAO_ADDRESS=0x65ce28a1d99a085a0d5b4d07ceb9b80a9ef0e64a525bf526cff678c619fc4b1
```

### Whitelist Collections

```bash
# Add whitelist
starkli invoke 0x0488317a379f653c7b98d2e0b8e77723cb016a93295c55ce95126ff024f66d78 whitelist_collection $BEASTS_ADDRESS --account ./account
starkli invoke 0x00a342cdd1abf7fc694c582226d88b56c503d430a5f301ddcbb3cb589d99dabe whitelist_collection $BEASTS_ADDRESS --account ./account-mainnet

# Mainnet hash
starkli deploy 0x04624b17451699a93ea17a444ee8503a6d9317c1f8eb7fc4d27269d1a46b1cc3 $LORDS_ADDRESS 300 $DAO_ADDRESS --account ./account-mainnet
```
