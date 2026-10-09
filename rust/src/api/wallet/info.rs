use flutter_rust_bridge::frb;

use crate::api::structs::network::Network;
use crate::api::structs::silent_payment_code::SilentPaymentCode;

use super::SpWallet;

impl SpWallet {
    #[frb(sync)]
    pub fn get_receiving_address(&self) -> SilentPaymentCode {
        self.client.receiving_code().into()
    }

    #[frb(sync)]
    pub fn get_change_address(&self) -> SilentPaymentCode {
        self.client.change_code().into()
    }

    #[frb(sync)]
    pub fn get_network(&self) -> Network {
        self.client.network().into()
    }
}
