#!/usr/bin/env bash
set +ex

#########################################################
#                                                       #
#                 BEGIN CONFIGURATION                   #
#                                                       #
#########################################################

#Addresses of Oracle Medianizer Contracts to Configure
#BALUSD="0x47e5a70Ac1D912A15051fc56a08321c2210Eb5e5"
YFIUSD="0x029C6EF55d0F3940ECA445567951C1eb87F49462"

ORACLES=( "$YFIUSD" )

NETWORK=MAINNET

#gas price
#check ethgasstation.info to set the correct value
ETH_GAS_PRICE=$(seth --to-wei 22 "gwei")

#gas limit
ETH_GAS=1500000

#address(es) of entites to whitelist
CONSUMERS=()

#address of existing owner of smart contract(s)
OWNER="0x0048d6225D1F3eA4385627eFDC5B4709Cab4A21c"

#address(es) of new owners to add
DSPAUSEPROXYMAINNET="0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB"
DSPAUSEPROXYKOVAN="0x0e4725db88Bb038bBa4C4723e91Ba183BE11eDf3"
DSPAUSEPROXYROPSTEN="0x0202CA66a683EB17B4488Ce6807f733c24958574"

#rpc url for eth client
ETH_RPC_URL="https://kovan.infura.io/v3/7e7589fbfb8e4237b6ad945825a1d791"

case $NETWORK in
	#1. fill in who should be set as Oracle owner
	#in most cases this is exclusively the DSPauseProxy
	#2. set rpc url
	#3. select which Spotter to use
	MAINNET) {
		ETH_RPC_URL="https://mainnet.infura.io/v3/7e7589fbfb8e4237b6ad945825a1d791"
		SETOWNERS=( "$DSPAUSEPROXYMAINNET" )
		SPOTTER="0x65c79fcb50ca1594b025960e539ed7a9a6d434a3"
	};;
	KOVAN) {
		ETH_RPC_URL="https://kovan.infura.io/v3/7e7589fbfb8e4237b6ad945825a1d791"
		SETOWNERS=( "$DSPAUSEPROXYKOVAN" )
		SPOTTER="0x3a042de6413eDB15F2784f2f97cC68C7E9750b2D"
	};;
	ROPSTEN) {
		ETH_RPC_URL="https://ropsten.infura.io/v3/7e7589fbfb8e4237b6ad945825a1d791"
		SETOWNERS=( "$DSPAUSEPROXYROPSTEN" )
		SPOTTER=""
	};; 
	*) {
    echo >&2 "Error: network not recognised: $NETWORK"
  	};;
 esac

#########################################################
#                                                       #
#                  END CONFIGURATION                    #
#                                                       #
#########################################################

function join { local IFS=","; echo "$*"; }
	
for oracle in "${ORACLES[@]}"; do
    
	#build and deploy OSM contract
	cd /Users/nkunkel/Programming/osm || exit
	echo "Building OSM contract"
	dapp build
	echo "Deploying OSM"
	osm=$(dapp create OSM "$oracle" -G 3000000)

	#verify OSM contract was deployed
	if [[ ! "$osm" =~ ^(0x){1}[0-9a-fA-F]{40}$  ]]; then
		echo "Error - Failed to deploy OSM contract. Invalid address $osm"
		exit
	fi

	echo "Successfully deployed OSM at address $osm"

	#verify owner of OSM contract
	echo "Verifying owner of OSM: $osm"
	owner=$(seth --to-dec "$(seth --rpc-url "$ETH_RPC_URL" call "$osm" "wards(address)(uint)" "$OWNER")")
	if [[ "$owner" -ne "1" ]]; then 
		echo "Error - $OWNER is not owner of OSM: $osm"
		exit
	fi

	#set owner(s) of OSM (default = DSPauseProxy)
	for owner in "${SETOWNERS[@]}"; do
		echo "Setting owner $owner for OSM $osm"
		seth --rpc-url "$ETH_RPC_URL" --gas "$ETH_GAS" --gas-price "$ETH_GAS_PRICE" send "$osm" "rely(address)" "$owner"
	done

	#verify new owner(s)
	for owner in "${SETOWNERS[@]}"; do
		isOwner=$(seth --rpc-url "$ETH_RPC_URL" call "$osm" "wards(address)(uint)" "$owner")
		if [[ "$isOwner" -ne "1" ]]; then 
		echo "Error - $owner is not owner of OSM: $osm"
		exit
	fi
	done

	#whitelist spotter in OSM
	echo "Whitelisting Spotter ($SPOTTER) for OSM $osm"
	seth --rpc-url "$ETH_RPC_URL" --gas "$ETH_GAS" --gas-price "$ETH_GAS_PRICE" send "$osm" "kiss(address)" "$SPOTTER"

	#verify spotter is whitelisted in OSM
	echo "Verifying Spotter is Whitelisted on OSM"
	if [[ $(seth --rpc-url "$ETH_RPC_URL" call "$osm" "bud(address)(uint256)" "$SPOTTER") -ne 1 ]]; then
		echo "Error - Failed to whitelist Spotter ($SPOTTER) on OSM ($osm)"
		exit
	fi

	#whitelist consumers in OSM
	for consumer in "${CONSUMERS[@]}"; do
		echo "Whitelisting $consumer for OSM: $osm"
		seth --rpc-url "$ETH_RPC_URL" --gas "$ETH_GAS" --gas-price "$ETH_GAS_PRICE" send "$osm" "kiss(address)" "$consumer"
		echo ""
	done

	#verify consumers are whitelisted in OSM
	for consumer in "${CONSUMERS[@]}"; do
		"Verifying Consumer ($consumer) is Whitelisted in OSM"
		if [[ $(seth --rpc-url "$ETH_RPC_URL" call "$osm" "bud(address)(uint256)" "$consumer") -ne 1 ]]; then
			echo "Error - Failed to whitelist Consumer ($consumer) on OSM ($osm)"
			exit
		fi
	done

	#whitelist OSM in Medianizer
	echo "Whitelisting OSM on Medianizer ($oracle)"
	seth --rpc-url "$ETH_RPC_URL" --gas "$ETH_GAS" --gas-price "$ETH_GAS_PRICE" send "$oracle" "kiss(address)()" "$osm"

	#verify OSM is whitelisted in Medianizer
	if [[ $(seth --rpc-url "$ETH_RPC_URL" call "$oracle" "bud(address)(uint256)" "$osm") -ne 1 ]]; then
		echo "Error - Failed to whitelist OSM ($osm) on Medianizer ($oracle)"
		exit
	fi

	#poke OSM
	echo "Poking OSM ($osm)"
	seth --rpc-url "$ETH_RPC_URL" --gas "$ETH_GAS" --gas-price "$ETH_GAS_PRICE" send "$osm" "poke()()"

	#verify OSM has queued price
	storage=$(seth --rpc-url "$ETH_RPC_URL" storage "$osm" 0x4)
	if [[ ! "$storage" =~ ^(0x){1}[0-9a-fA-F]{64}$ ]]; then
		echo "Error - failed to query valid queued price storage ($storage) from OSM ($osm)"
		exit
	fi
	price=$(seth --from-wei "$(seth --to-dec "${storage:34:32}")")
	if [[ ! "$price" =~ ^([1-9][0-9]*([.][0-9]+)?|[.][0-9]*[1-9]+[0-9]*)$ ]]; then
		echo "Error - OSM returned invalid queued price ($price)"
		exit
	fi
	echo "OSM has queued price $price"

	echo ""
	echo "//////////////////////////////////////////"
	echo ""
	echo "SCUCCESSFULLY DEPLOYED OSM at $osm"
	echo ""
	echo "//////////////////////////////////////////"
	echo ""
done
