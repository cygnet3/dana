use flutter_rust_bridge::frb;

use crate::api::structs::network::ApiNetwork;

use super::SpWallet;

impl SpWallet {
    #[frb(sync)]
    pub fn get_birthday(&self) -> u32 {
        self.birthday.to_consensus_u32()
    }

    #[frb(sync)]
    pub fn get_receiving_address(&self) -> String {
        self.client.get_receiving_address().to_string()
    }

    #[frb(sync)]
    pub fn get_change_address(&self) -> String {
        self.client.sp_receiver.get_change_address().to_string()
    }

    #[frb(sync)]
    pub fn get_network(&self) -> ApiNetwork {
        self.client.get_network().into()
    }
}
