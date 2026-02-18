use anyhow::Result;
use flutter_rust_bridge::frb;
use spdk_core::silentpayments::Network as SpNetwork;
use spdk_core::RecipientAddress;

use crate::api::structs::network::ApiNetwork;

#[frb(sync)]
pub fn validate_address_with_network(address: String, network: ApiNetwork) -> Result<()> {
    log::debug!(
        "address_with_network: address: {}, network: {:?}",
        address,
        network
    );
    let address = RecipientAddress::try_from(address);

    match address {
        Ok(RecipientAddress::LegacyAddress(legacy_address)) => {
            legacy_address.require_network(network.into())?;
            Ok(())
        }
        Ok(RecipientAddress::SpAddress(sp_address)) => match (sp_address.get_network(), &network) {
            (SpNetwork::Mainnet, ApiNetwork::Mainnet)
            | (SpNetwork::Testnet, ApiNetwork::Testnet3)
            | (SpNetwork::Testnet, ApiNetwork::Testnet4)
            | (SpNetwork::Testnet, ApiNetwork::Signet)
            | (SpNetwork::Regtest, ApiNetwork::Regtest) => Ok(()),
            (sp_network, _) => Err(anyhow::anyhow!(
                "Wrong network, expected: {:?}, got: {:?}",
                network,
                sp_network,
            )),
        },
        Ok(RecipientAddress::Data(_)) => {
            Err(anyhow::Error::msg("Sending to OP_RETURN not allowed"))
        }
        Err(e) => Err(e),
    }
}

#[frb(sync)]
pub fn is_reusable_payment_code(address: String) -> bool {
    matches!(
        RecipientAddress::try_from(address),
        Ok(RecipientAddress::SpAddress(_))
    )
}
