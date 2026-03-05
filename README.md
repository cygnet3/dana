# Dana wallet

Dana is a flutter app used for accepting bitcoin donations. It uses silent payments, a new static payments protocol, to receive donations while preserving on-chain privacy.

## Try out Dana wallet

> [!WARNING]
> Dana wallet is currently still considered 'experimental'.
> Don't use funds you aren't willing to lose.
> We don't take responsibility for lost funds.

We are looking into releasing Dana wallet on the popular app stores once the app is more stable.

In the meantime, there are three ways to try out Dana wallet:

- Using Obtanium, download the latest release from GitHub
- Manually download the latest Dana wallet APK from the [releases page](https://github.com/cygnet3/danawallet/releases)
- Using F-Droid, download Dana wallet using our [self-hosted F-Droid repository](https://fdroid.danawallet.app/fdroid/repo)

Downloading the APK from the releases page is probably the easiest option.
However, for some extra options (e.g. if you want to test using Signet), you'll need to use the F-droid repository option. More info below.

### Test using Signet

If you downloaded the latest release on GitHub, you will be using Mainnet.
This means you are working with real bitcoin.
Perhaps to make testing easier, you prefer to use fake coins instead.
For this, we provide a special 'Signet' flavor for Dana.
This Signet flavor can be found on our self-hosted F-Droid repository.
See the 'Adding our F-Droid repository' section on how to add our repository and download the Signet flavor.

### Getting Signet coins to test

Of course, in order to actually test the wallet, you will probably need some test coins.
To get some coins, you can use our silent payments faucet:

https://silentpayments.dev/faucet/signet

Signet is a test network, but tries to emulate the behavior of the real bitcoin network.
After claiming some funds, you will have to wait for the next block confirmation before they appear on Dana.
If they do not appear after a few confirmed blocks, please reach out to us,
as this may imply there's an issue with the faucet.

#### Adding our F-Droid repository

- Open F-Droid on your android phone
- Go to 'Settings'
- In the 'My Apps' section, click on 'Repositories'
- Add a new repository by clicking the '+' icon
- Scan the QR code found on this page: https://fdroid.danawallet.app/fdroid/repo

#### App flavors

There are 3 app 'flavors' hosted on our F-droid repository:

- 'Dana wallet', this is the default flavor, and is identical to the APK released on GitHub. Uses Mainnet (real bitcoin).
- 'Dana wallet - Experimental', this flavor has some additional extra advanced options/features. Some of these features may not be stable and are not necessarily expected to end up in the stable releases. Uses Signet by default, but allows user to change the network.
- 'Dana wallet - Signet', this flavor is for using the Signet network.

## Building Dana wallet from source

Below are some instructions to build Dana wallet from souce. This is only recommended if you want to want to help out with development for Dana wallet.

### Building for linux (desktop)

Building for linux should require no extra effort, simply execute

```
fvm flutter run
```

This may also work on other platforms (macOS, Windows), but we have not tested this.

### Building for android

Building for an android device requires some preparatory work, to generate binaries for this architecture.

First, you need `cargo-ndk`. You may also need to add your desired toolchains:

```
cargo install cargo-ndk
rustup target add \
    aarch64-linux-android \
    armv7-linux-androideabi \
    x86_64-linux-android \
    i686-linux-android
```

After these are installed, you can generate the binaries using

```
just build-android
```

If you don't have `just` installed, you can also copy the commands found in the `justfile`.
This generates the binaries.

Next, connect your phone and enable debugging mode.
Check if you phone is connected by running

```
fvm flutter devices
```

Finally, to build and install the app for your android device:

```
just run
```

## Donate to Dana

You can donate to Dana wallet using our BIP353 address:

> ₿donate@danawallet.app

or you can use the following silent payment-address:

> sp1qq0cygnetgn3rz2kla5cp05nj5uetlsrzez0l4p8g7wehf7ldr93lcqadw65upymwzvp5ed38l8ur2rznd6934xh95msevwrdwtrpk372hyz4vr6g
