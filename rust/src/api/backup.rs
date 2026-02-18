use base64::Engine;
use crypto::{
    aes, blockmodes,
    buffer::{self, BufferResult, ReadBuffer, WriteBuffer},
    digest::Digest,
};
use flutter_rust_bridge::frb;
use rand::{rngs::OsRng, TryRngCore};
use serde::{Deserialize, Serialize};

use crate::api::structs::network::ApiNetwork;

use super::{
    history::TxHistory,
    outputs::OwnedOutputs,
    wallet::{ApiScanKey, ApiSpendKey, SpWallet},
};

use anyhow::Result;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct EncryptedDanaBackup {
    pub iv_base64: String,
    pub content_base64: String,
}

impl EncryptedDanaBackup {
    #[frb(sync)]
    pub fn new(iv_base64: String, content_base64: String) -> Self {
        Self {
            iv_base64,
            content_base64,
        }
    }

    #[frb(sync)]
    pub fn decrypt(self, password: String) -> Result<DanaBackup> {
        let decoder = base64::engine::general_purpose::STANDARD;

        let mut key = [0u8; 32];
        let mut sha256 = crypto::sha2::Sha256::new();
        sha256.input_str(&password);
        sha256.result(&mut key);

        let iv = decoder.decode(self.iv_base64)?;
        let content = decoder.decode(self.content_base64)?;

        let mut final_result = Vec::<u8>::new();
        let mut read_buffer = buffer::RefReadBuffer::new(&content);
        let mut buffer = [0; 4096];
        let mut write_buffer = buffer::RefWriteBuffer::new(&mut buffer);

        let mut decryptor =
            aes::cbc_decryptor(aes::KeySize::KeySize256, &key, &iv, blockmodes::PkcsPadding);

        loop {
            let result = decryptor
                .decrypt(&mut read_buffer, &mut write_buffer, true)
                .unwrap();
            final_result.extend(
                write_buffer
                    .take_read_buffer()
                    .take_remaining()
                    .iter()
                    .map(|&i| i),
            );
            match result {
                BufferResult::BufferUnderflow => break,
                BufferResult::BufferOverflow => {}
            }
        }

        DanaBackup::decode(String::from_utf8(final_result)?)
    }

    #[frb(sync)]
    pub fn encode(&self) -> Result<String> {
        Ok(serde_json::to_string(&self)?)
    }

    #[frb(sync)]
    pub fn decode(encoded: String) -> Result<Self> {
        Ok(serde_json::from_str(&encoded)?)
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DanaBackup {
    // version number to mark backwards incompatible versions
    version: u32,
    #[serde(flatten)]
    pub wallet: WalletBackup,
    #[serde(flatten)]
    pub settings: SettingsBackup,
}

impl DanaBackup {
    #[frb(sync)]
    pub fn new(wallet: WalletBackup, settings: SettingsBackup) -> Self {
        Self {
            version: 1,
            wallet,
            settings,
        }
    }

    #[frb(sync)]
    pub fn encrypt(&self, password: String) -> Result<EncryptedDanaBackup> {
        let data = self.encode()?;

        let mut key = [0u8; 32];
        let mut iv = [0u8; 16];

        // pick a random IV
        OsRng.try_fill_bytes(&mut iv)?;

        let mut sha256 = crypto::sha2::Sha256::new();
        sha256.input_str(&password);
        sha256.result(&mut key);

        let mut final_result = Vec::<u8>::new();
        let mut read_buffer = buffer::RefReadBuffer::new(data.as_bytes());
        let mut buffer = [0; 4096];
        let mut write_buffer = buffer::RefWriteBuffer::new(&mut buffer);

        let mut encryptor =
            aes::cbc_encryptor(aes::KeySize::KeySize256, &key, &iv, blockmodes::PkcsPadding);

        loop {
            let result = encryptor
                .encrypt(&mut read_buffer, &mut write_buffer, true)
                .unwrap();

            final_result.extend(
                write_buffer
                    .take_read_buffer()
                    .take_remaining()
                    .iter()
                    .map(|&i| i),
            );

            match result {
                BufferResult::BufferUnderflow => break,
                BufferResult::BufferOverflow => {}
            }
        }

        let encoder = base64::engine::general_purpose::STANDARD;

        Ok(EncryptedDanaBackup {
            iv_base64: encoder.encode(iv),
            content_base64: encoder.encode(final_result),
        })
    }

    #[frb(sync)]
    pub fn encode(&self) -> Result<String> {
        Ok(serde_json::to_string(&self)?)
    }

    #[frb(sync)]
    pub fn decode(encoded_backup: String) -> Result<Self> {
        Ok(serde_json::from_str(&encoded_backup)?)
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct WalletBackup {
    pub scan_key: ApiScanKey,
    pub spend_key: ApiSpendKey,
    pub birthday: u32,
    pub network: ApiNetwork,
    pub tx_history: TxHistory,
    pub owned_outputs: OwnedOutputs,
    pub seed_phrase: Option<String>,
    pub last_scan: u32,
}

impl WalletBackup {
    #[frb(sync)]
    pub fn new(
        wallet: SpWallet,
        network: ApiNetwork,
        tx_history: TxHistory,
        owned_outputs: OwnedOutputs,
        seed_phrase: Option<String>,
        last_scan: u32,
    ) -> Self {
        Self {
            scan_key: wallet.get_scan_key(),
            spend_key: wallet.get_spend_key(),
            birthday: wallet.get_birthday(),
            network,
            tx_history,
            owned_outputs,
            seed_phrase,
            last_scan,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SettingsBackup {
    pub blindbit_url: Option<String>,
    pub dust_limit: Option<u32>,
}

impl SettingsBackup {
    #[frb(sync)]
    pub fn new(blindbit_url: Option<String>, dust_limit: Option<u32>) -> Self {
        Self {
            blindbit_url,
            dust_limit,
        }
    }
}
