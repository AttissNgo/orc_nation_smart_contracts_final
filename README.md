## New contract addresses and ABI files
Everything can be found in the `json_out` directory. No need to compile contracts to get the ABIs.

## Polygon Mainnet to-do's

Shree 
- Connect portal to new contracts
- Mint should permit a maximum of 10 tokens per transaction
- Whitelisted users can only mint 3 tokens TOTAL during presale (after that they can mint as many as they want)

Trevor
- Connect team portal to new contracts
- Confirm with Johan that whitelisting functionality is working (this can be done even after presale ends)

Attiss
- add correct URI to deployment script
- add correct Chainlink VRF subscription ID to deployment script
- create new RPC with Alchemy or Infura
- double-check and confirm payee addresses & share percentages


Johan
- create .env file for PKs & RPC
- setup up Chainlink VRF subscription and fund with LINK
- add deployed contract addresses (Orc Nation and Raffle) as consumers 

## Minting 500 'owner' tokens
The following script can be run by any admin:
```
forge script script/OwnerMint.s.sol:OwnerMint --sig "mint(string)" "mumbai" --rpc-url $MUMBAI_RPC_URL --broadcast
```