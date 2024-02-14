# Off-chain Raffle 
## Abstract
All raffle functionality has been moved off-chain. Raffles will be drawn programatically using an open-source program. This allows us the flexibility to re-draw raffles if the winner does not claim their prize within 30 days.
## Control flow
When token threshold is reached, a raffle drawing program may be called by an admin. The program will read from Orc Nation to get the buyer addresses, generate a random number and assign it to one of those addresses. In the case of free tokens (@ 2000 sold), the winning addresses may be added to Orc Nation (via Governor). In the case of cash prizes, the winners will be selected in the same way, the Company will withdraw the prize money from the Payment Splitter (via Governor) and send directly to the winner.

# Contract addresses and ABI files
Everything can be found in the `json_out` directory. No need to compile contracts to get the ABIs.



## Minting 500 'owner' tokens
The following script can be run by any admin:
```
forge script script/OwnerMint.s.sol:OwnerMint --sig "mint(string)" "mumbai" --rpc-url $MUMBAI_RPC_URL --broadcast
```