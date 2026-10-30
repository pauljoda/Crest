import XCTest

@testable import Crest

/// The SRP exchange against vectors produced by the reference implementation
/// (the JavaScript the protocol was reverse engineered in), run with fixed
/// randomness. The salt starts with a zero byte on purpose.
///
/// Four vectors cover the padding rules where interop breaks: the minimal
/// encoding of A, of B and of S is one byte short of the group's width in
/// the vector named for it, and the session key starts with a zero byte in
/// the last. Seeds, as `sha256("crest-apple-passwords-vector/<label>/<n>")`:
/// ordinary a=0 b=0; shortA a=328; shortB b=71; shortS a=248 b=0;
/// leadingZeroK a=187 b=1.
final class ApplePasswordsSRPTests: XCTestCase {
    private struct SRPVector {
        let name: String
        let privateKey: String
        let serverPublicKey: String
        let clientPublicKey: String
        let scrambler: String
        let sharedSecret: String
        let sessionKey: String
        let clientProof: String
        let serverProof: String
    }

    private static let identity = "0xeafee6f34c3c2bd45594013e304c58ae"
    private static let code = "042917"
    private static let salt = "001f6bbf61520c1a0d8dbdfa0eae32bd"
    private static let multiplier = "081f4874fa543a371b49a670402fda59ecfab53a1b850fc42e1c357cc846111e"
    private static let privateExponent = "a24ba0ad5bcdf30b0a561180a573e231e24822d76c635cdf562d8d2eefbd0b73"

    private static let vectors: [SRPVector] = [
        SRPVector(
            name: "ordinary",
            privateKey: "7511c046cd47ded9c779c5a2c7f689c316eea06bddb536edfab5317475100fae",
            serverPublicKey: """
                ab48db0e6e12e94436292125cf42ba7f8570045298d614f0decd7113d0b62325974394b5fdf6bd7b\
                5c23e90875f7ef91b0e2d8275588a55c7b636a75528fb031772343e3b502ec03fb160ab6de873801\
                f8ebc0d6d4d9b64d16ad240c59c45b71356f1944ed6b22c16a815c863671d1bea7734a4149e55617\
                2af7ccb89b0e226556135fd651c2a22727bb5153579e3302191c91ffbb1fe5b672655ef8484f6f6b\
                e52d05f3291d9b6be9f15ae694fdfb90e92e7cc732ef0395586ae5c6bf2537332ecde5eed0731458\
                f6e6b36e97b38724a98b6933b37c012598acbc843042eeb271cfe132b95c3696f50d2a8fcca668fc\
                f0d277649b3f4c46b7920958997a2003ebf3ef5491b31c2a6a51fbe79d7e39190d0aafde5fee5dd8\
                849e2c2de812627a35209aaec9b734dd58c6de6ab28d6d5091bd6febcd058b8a496302a39b5488f1\
                b1bf6d0b763c68cde6da9f00b4d7b8ba3a7849ae2770a5ed6721ddf02ce4ad23c627ea89b6a92a14\
                b5c4ec529e3ae86b6d4bfb0174115bba857e264a3588cb7a
                """,
            clientPublicKey: """
                9ea7efeffb32deb6364fd64d3297fa63dcce99af942362dbf5902c9cbf6f18a00c40fef4b547c564\
                9d7c9b65e2aadf5b9a6504f04864a3cdef3eb3207dc708c63ca4662ad387a56c4898e97937108454\
                7aaf3ff822c83c0bc1020e32f2c216c57beaf70acfe66c6270f2d743c5cd8b56f3708bb14181511f\
                a06d768f85be12467255f30c3b34bc75c5746c378a8614ce998871810b89795a5b4261fd4f3cb4e1\
                2755a265f2188b8948ac803f15c194abd3f3ce602b840ed1920fdb37620b8eb9b7f0aea5e1bdb248\
                69dcf31acada97c41fc7d4de672990530a70f2dbc5d48f24dde1326cd795a8e8d70dace9a5cacb92\
                3c785bbea533ff51c546a242434120988430d3f3b5c92e656dd1288f814870c02a0ee39615275f68\
                ab01601cb1528bddd36a7528076c8103c357040b74db82fa1a233482fe7ca4408c0b866345fc6e25\
                75199b96f2ccdce9ce4a13b6a1817a6c9b0cb5a08302f17f2be6cd5bc4c0fc23478224f4cbb4f482\
                f5d77b7ae5b4fbd7a5c30d57a500add919e4696cf37d55e1
                """,
            scrambler: "2399690a35e1e004cc3bb7a3ba575fb28d89251594471ee7e38331c317a38225",
            sharedSecret: """
                62df37761faadc5aa9ddaca1baf808db3efeffcf7c972a97eb8f19661bc69added3c952c74a06488\
                60c13848bcfeb8efad261bdc2b29f22019a824ae66cd781384aaa3571b796be1464a890b0634b208\
                ec40d498c3bcdd3ffe91dbbb5a147ecf9c70c93a4aee73dfb1299c55df6ec1b641ed40f7f06dd390\
                0d17c6bf66089d8ce0aa2527255747757ea8ae1657132471404581dfde54146e3e2b500aa1ef70c7\
                275cc783b65295957db444b838b1b811d2979263e45422768a30937cf6ac23283e1c93b32422c451\
                1283c868f6c66afa97a5e663428cd6b23c9fef17cac05cbb167b45acabe24c5432faf3a3a2e1d02b\
                64f8f08097c474244b528d730ef16b906cbd07c25b0362e6c63c41c5aa8325a9d5c5d02b55c8a2fe\
                e503927d1882fca242fe52e105e1ada21985b588662ccd35db49256f8657b1c325769f6d19738f2d\
                e751bc5f1ff155bca005266798aa2f72ff2e4fb5a3e6fcf667200b1bbf29e049767db0a85d3813f7\
                788ed2ec8f930eefac7309ac216c8aabb59062fb8aeb73b1
                """,
            sessionKey: "5039237db56993e2fc2ea9b4eb9f9edafa9a4e31cc8e98d1ee5ef2bd6c46d08b",
            clientProof: "228e7749ad5039232934a201a4c0fe00c359f3080ed739a3e7db22cbe0078817",
            serverProof: "986d9097006fca84eb15f44cffb236ba671c37d4d1eec14ed3e534993b9a1dd8"
        ),
        SRPVector(
            name: "shortA",
            privateKey: "7e01051fc522b4048f7d6160b3e58534ef91e941d17278e965ed96ff37396191",
            serverPublicKey: """
                ab48db0e6e12e94436292125cf42ba7f8570045298d614f0decd7113d0b62325974394b5fdf6bd7b\
                5c23e90875f7ef91b0e2d8275588a55c7b636a75528fb031772343e3b502ec03fb160ab6de873801\
                f8ebc0d6d4d9b64d16ad240c59c45b71356f1944ed6b22c16a815c863671d1bea7734a4149e55617\
                2af7ccb89b0e226556135fd651c2a22727bb5153579e3302191c91ffbb1fe5b672655ef8484f6f6b\
                e52d05f3291d9b6be9f15ae694fdfb90e92e7cc732ef0395586ae5c6bf2537332ecde5eed0731458\
                f6e6b36e97b38724a98b6933b37c012598acbc843042eeb271cfe132b95c3696f50d2a8fcca668fc\
                f0d277649b3f4c46b7920958997a2003ebf3ef5491b31c2a6a51fbe79d7e39190d0aafde5fee5dd8\
                849e2c2de812627a35209aaec9b734dd58c6de6ab28d6d5091bd6febcd058b8a496302a39b5488f1\
                b1bf6d0b763c68cde6da9f00b4d7b8ba3a7849ae2770a5ed6721ddf02ce4ad23c627ea89b6a92a14\
                b5c4ec529e3ae86b6d4bfb0174115bba857e264a3588cb7a
                """,
            clientPublicKey: """
                e8942319315443c30c1cc3c1c689d37ae63878a87608f376391e7c3ebb134a415b279c7f1510abe0\
                418f44a2d8f4667a95a5be87a7249b0acf38073d003e4c66e4e2a082af4f7e13fcca84acb9deef5e\
                7da0191377273cfddcc1d6f605df5e639ed3dd1362d47cf0bc66b613903609c84f399d76895ae55a\
                915f7e1f7062b001fddae8db30e74c1c447173bb9c58a5f5d1f424460033d5457e9e693af0809822\
                2669731c8444eb27d0df12e9909dbfac9691c6722a6292b156bb18a6e61641b0dfae2588a8bab164\
                8a2e7578164472ce1347e59e3201503cd4ff041c81ae63693ca0145ed3862cdf369c9994955e742e\
                76b912f6b53aafd9f529267e5801ce2b4b23466218d2510f21ce8a5ad315b77f786b6e339634e49e\
                b2651292a8984e5df39a99777807e9cb96e61ae59b544bc891978242eb53dd204b09876558a3ae0f\
                9b729d1889637ba601cf0bf71f9905aa9ab63e4efc38a794ec4a9f6f08456e9b1a7df1f301d1a1cd\
                722088b8aa191b5fa0e977866943f780eb2f8cb1661b4c
                """,
            scrambler: "6e1d872692f440c7e23e0de52bca11e298dc977f74d58e43c7427565843dec57",
            sharedSecret: """
                4fe3f3d1066bbd11a94b46da8cf974347114f215702d487f19d6395fc3009a52fa3a1137531abe87\
                f5dc57b8261d0ed8b307b4215536753930b3d6802da2f9708fd0f2047707dd6194f3b4b10ecea524\
                521183f1b735afe51967b957c2ad2c7903bb49aeed84a2edd141c5d88d09153a0860138a22fe5ffd\
                7ab8d58f90667b4d5ad31ad2939cce5883220b98357957cf00b7b989e8c1ee004f419d2a4f49dd5d\
                f5bf55dca9975521af2a2cee9470d8d850d0c2309225949c06563244bcb7cb4e2db0eeae51f02f66\
                df9ab55b14e4175b0c8071cf25da7bbb2eb34304df1287d56aad65880d8853890a14d9b9535bc09b\
                e36e43e77e4711dd6206f68747167353132cda6425d76a3e816b8bc719f2669233efc62703a8facb\
                a86de50795fd10b3cd2803aa4395031ebb814785a5eaa0c8dbac79ca260473182ae042e9f646b2df\
                8fb409f8e4e563eddd0acc0a695557663748c3612b449233cca3f38e898f798e879d053a128ad314\
                b6ad8715e926be066bc336e50270d94c4ce2268c5fbf4e00
                """,
            sessionKey: "f9cefb2e1628a110d53bb470b88a605f5381f0906b979be1c6b3e3c1010b2897",
            clientProof: "5fc74b9994e74a918cd12601d52c481fe2f9e421c22d9e70552c54ac1fda9aed",
            serverProof: "fc507f30af878155f5df71d77eedc992f4c167ef2fe434d9b075de940e41cf3a"
        ),
        SRPVector(
            name: "shortB",
            privateKey: "7511c046cd47ded9c779c5a2c7f689c316eea06bddb536edfab5317475100fae",
            serverPublicKey: """
                81a57dc838d7d539e0d3744dc178bff3cbe02407221577725c32ea6f8a455b8ddb0c9105c958b981\
                3662ce019d10b146c84844a33321bfa0f6802b561b77a1d740d2e4d44e66eaabaf895eeff8b26691\
                e825ebe844c583bad0d420e211c964dc55d7d6c8df36452ab035800d423ad8c5b1d5baa7738b47b2\
                9dc3c08dced60f2a27f312598b07b8e1de6f5150754f347c8f8d404d9e004fcff20bcdd847bd91dd\
                95ee367d64dce13735614d3d2656671c5b2306eb97c7c7202f243ea653f3dc51e69febef5c699eab\
                3429f922b757584b30d7b66f9f1a550a7fb207d002010d9424319e3ff9263af9cdc0bb9b21da3453\
                76261daed4516c4b3c138c5c3b45e876dd90b8d8012c8fbbd111425620b2c25023d43fa801b6d1e8\
                6594d7b9ed901689b6b24d3b8c6543f5400e130201b696ee62bbe2fc51c970f2df8120a2ed245bd3\
                b82d4fb0d2af05c0e10f9ae47380eeccea29c299ce61208b59ad6cc9fa9a4d8d293c137c91d9ff82\
                b91fdebcc80cbf4f63e9d74a1cebf9f29999252cbcc461
                """,
            clientPublicKey: """
                9ea7efeffb32deb6364fd64d3297fa63dcce99af942362dbf5902c9cbf6f18a00c40fef4b547c564\
                9d7c9b65e2aadf5b9a6504f04864a3cdef3eb3207dc708c63ca4662ad387a56c4898e97937108454\
                7aaf3ff822c83c0bc1020e32f2c216c57beaf70acfe66c6270f2d743c5cd8b56f3708bb14181511f\
                a06d768f85be12467255f30c3b34bc75c5746c378a8614ce998871810b89795a5b4261fd4f3cb4e1\
                2755a265f2188b8948ac803f15c194abd3f3ce602b840ed1920fdb37620b8eb9b7f0aea5e1bdb248\
                69dcf31acada97c41fc7d4de672990530a70f2dbc5d48f24dde1326cd795a8e8d70dace9a5cacb92\
                3c785bbea533ff51c546a242434120988430d3f3b5c92e656dd1288f814870c02a0ee39615275f68\
                ab01601cb1528bddd36a7528076c8103c357040b74db82fa1a233482fe7ca4408c0b866345fc6e25\
                75199b96f2ccdce9ce4a13b6a1817a6c9b0cb5a08302f17f2be6cd5bc4c0fc23478224f4cbb4f482\
                f5d77b7ae5b4fbd7a5c30d57a500add919e4696cf37d55e1
                """,
            scrambler: "cc662c5d6a3ed928a9e9316ef536e99e029788731958219c40eb5688c386a403",
            sharedSecret: """
                a45e9e472fbef843f83c82948910c93beaaa23d05b2fb3cdb70eb919d04475a7d5bcd0ff02229ba1\
                66132730b5217f3b75b5d22da0b5c1e796372f788fb1b8e7a25e9aa3786ebc94d2060d8b220efd0b\
                1d0cd01d94f02f785f9f047cf2eb82cd5638a9564e0889dca881774cbf63871b664d64438e296d39\
                1494825810fe60eac467a6cc5c7530110c1c0f2257b3f3f1bf2a5f9669ed3e33077314f75e321363\
                114847c9040af6f926fbc3beda3e5349ec78bb158e3a0f871763f5ddffa8634605e512dac4970b83\
                a91bbef961bb1a803edd20c7557c9ba3e936ac35a9470372af5404581662da7394425fca7fd44ef6\
                cae6f9a1d417453f4b7bfc3b5b964ca6db185f2a8ebef1f2bab518fb0138fdcfc22d7bcba309a0b1\
                6b7593d1f97efbd3a31c81c9ab86d9a8eb00e929e7efbf5d8c649c7642764057547c161bd75b4ab4\
                97d4f4587a8d9a3c47d235b96aa04f170f6ef9d646d80643e8093d85a78aad27420dab2cc90a7ce3\
                b2c60c9a13a26e73617a5ff15f6a07416d18d009c56bca92
                """,
            sessionKey: "136c17289c52a097811e566e974d88096dc9c919358e77b2c3be6699bb9456c6",
            clientProof: "6dfd142d53bdc37404e8092f5db8ea30841cad63fd7d37792b59119963473caa",
            serverProof: "5dcd57e5746bacd2d72f727a427353fbbdef0fc1f7f1ec306044284ef586dcbe"
        ),
        SRPVector(
            name: "shortS",
            privateKey: "77e28a2ffc3ff0c751e2c021d6dffb63eecba20ffc0aae38bcc9c58744bd1a70",
            serverPublicKey: """
                ab48db0e6e12e94436292125cf42ba7f8570045298d614f0decd7113d0b62325974394b5fdf6bd7b\
                5c23e90875f7ef91b0e2d8275588a55c7b636a75528fb031772343e3b502ec03fb160ab6de873801\
                f8ebc0d6d4d9b64d16ad240c59c45b71356f1944ed6b22c16a815c863671d1bea7734a4149e55617\
                2af7ccb89b0e226556135fd651c2a22727bb5153579e3302191c91ffbb1fe5b672655ef8484f6f6b\
                e52d05f3291d9b6be9f15ae694fdfb90e92e7cc732ef0395586ae5c6bf2537332ecde5eed0731458\
                f6e6b36e97b38724a98b6933b37c012598acbc843042eeb271cfe132b95c3696f50d2a8fcca668fc\
                f0d277649b3f4c46b7920958997a2003ebf3ef5491b31c2a6a51fbe79d7e39190d0aafde5fee5dd8\
                849e2c2de812627a35209aaec9b734dd58c6de6ab28d6d5091bd6febcd058b8a496302a39b5488f1\
                b1bf6d0b763c68cde6da9f00b4d7b8ba3a7849ae2770a5ed6721ddf02ce4ad23c627ea89b6a92a14\
                b5c4ec529e3ae86b6d4bfb0174115bba857e264a3588cb7a
                """,
            clientPublicKey: """
                73761c209b856d8c8557f13a0d44c8986482ece4c78e5820656e12ab53488b8498bebbeb0f7cb2f1\
                8f8fe804c5b047eac933f8a7993490d3f18d2fb994e4479574296725294284556250db65490b0838\
                a46eb5e4715c5a354e9ce02fec767ab80d8c9e4c6bb5816ee266b6a7389de3c20c1c894195184934\
                b37beef0fbec6f0b9ff6bc1b1c127b83d1082b6a900d286325826cc6460ef68de46ff55295baeaef\
                455807eb49f64610eb6a419b01111ad854f0587f87bafe2d440a53db35721ec4f63af39e723654cb\
                ad3360bad270e3bbe183395047b8545d51396ac4e0a89a341316344f2352dfdb3d0c280fd402fdd6\
                4c69f7b8a77f4edd5a73ad2bba4445d57918059b0c09cb5481faa62ce49b691b746916a4872ad9ee\
                33b0ed88b16e411830543dff8ea337a44181fad6016fa9911badb2481c509fd8263f5b0cf2bf7f31\
                71a13da862ff1d9e38a0416289ac29918b77e10a579132af421adeef9bfcbbcbb9c914d28758d34f\
                772e76d084b9d0529a1c96007ef80a07e7d58c811b406af5
                """,
            scrambler: "59f448a89f86282ed782c1d0009d905d96e3c396152ec9e8bebe80983a1ddfb2",
            sharedSecret: """
                f990f72f4767060449a1a95b36243e568ea30b6a3413b9c76033f8a09071d02797c0c4a8bc6cb7fd\
                16e610ad2d9cc0d7e76de8a607bf64ef72b01aebeac9f50885ea7a8b53c52106c4b4783788dc2aaa\
                15a1cb75aa714fdea60858631132691953e751517559405610b8625d3a3842530d701c2eb3798ceb\
                68bf04618a433060e04645afbfe2303f1fbbcd7d6e280bda31a9f4da1be3caa018de71e2c6ad4a35\
                c10820c078328441ebeb4bc106042702bc887f5cb42a3b6af9ef27d1a50e3f604b09b65462a193c1\
                dc97f2644a48c3f2dff4487fab34279e8b386f8e97fa7871811fc8931757a7b3659f3e5a8df13282\
                446d36ae58e45ba922ef129cebbdbd9505ae1a215ac75606722c5f05f57a8b37b93919e8c68d42e9\
                164dc776a35123ee91b5f7ac6a187c829d6933bcbee47373c1006796218c448a327c82b3bab0a561\
                15899d1ae92d51f625a19204dc6fd203e2bded53432f9f60c1baf6ec04bf01d4f76b1ee46c0b021e\
                1919678e4306c73ddb58a8f326c0d796498e5e08b05a99
                """,
            sessionKey: "1cd3a4620d2851565e5bdb245cdda050e09ed8ed7aa9f2a52859accc567ad2ca",
            clientProof: "bb8b6492c83f6d3ecce384e0a0b0996ccda0e6fb38eacf754fbb1059bf28b0d6",
            serverProof: "73faf86fb0b94a224e441ed3987996e59da87e6a3cf635455cc881fd49137406"
        ),
        SRPVector(
            name: "leadingZeroK",
            privateKey: "6d1ebbe415efc4a9f49df4df0804d536724dea16c95e61aae9de842daad03919",
            serverPublicKey: """
                2a0332d3d8f813da5ae4292419c8df00119bdf5bb714c711ca642ec6c42a03de504f57d2cf07e675\
                054db6c6e88cadd41eb66eb46e30596fa5cdfbbc618a883df2c05836d2567c75de77586fb314e4ef\
                29ef46dc413282fbb3d672621bf6864d92e35aa50b9bce19dc79eb50a8890b139701b8ded660189f\
                3f568e55e3c9f763894d89b2057c49a68ec957d5c537ff5390b1eb39a68a03ff8e91ecd12efd7115\
                6aff12eb9d210dfe0d092e761e1ef8dabb0579805a73a621dd2a9d346da80c4382a38db89df1cc32\
                60986a5da74427d74661eaf5ef13f7087fa5c04606047ba4d68da15b1d9fbcf4e1465feebe84c86e\
                589cb10fdcb861ba331b8396992fb8f5a3c35d63e233574ad803ba895dbb628090b45cc759484acc\
                6bd725f2cefdbb1d488c4565fae01539509ff2f0d45695b90b32144f9142c51bc5791a6b77e3d1c7\
                2263b958bf39a10bde42c84d72036277ea74da3b32264765cb47bd29a080c76a3ff0d09e444a6227\
                0a6b7b3c00e22c57d07f8ec2532d2962834ecb954c3b83fc
                """,
            clientPublicKey: """
                1cc2f294ed2466bc33b0a0d017f8f4e00730ddc4445b90cf7edc554c56a54c6b573aa81b5e9714c8\
                f2eab2770826b2e97b6a6b10101bd26c6d0bc82357f2939ad8f61de82119c0a451484df7fdc0c060\
                3e73a8fa0eadb0134011a0fc8d062f08082dab1c58708fe3fc6ffe491726023b5ef103878ca427e4\
                1c4d6a05427b79b6c21ad576b1b7e3dd46fe6e7a84e8389a0b8e58f8e61f7ab8669772ab4ca8d602\
                573525f7e46b63e4a8a396335a2a2634c11a3969e89197434e7b66e2afb44d734f9d450496d0fe25\
                4c2d07283bd217645c4a4fba8d8e5b44aa01522f0a9b5b96801c6705f85ef1c3250b251fc340eb32\
                de6f9bae4c9938c9b1da00c8f8def072c6d8be0332a774dc811124c4431b4a361b9be739a399e11f\
                fb6d0550b3b05ca41473169024c82626e98a3ab6bc83b5adcb0aebb50a10025a1ee275a968e536c4\
                fef746e6e900bb6d165fc9892d29af33b00b41e2df906e2f9092496f7b746c0ea78366b47f3f0904\
                37534af37e6c8bd4f63c2227aa9981cab5b8c0f9d734a822
                """,
            scrambler: "b0c724a26809565d1bf766062a5c6f056070e8dafb5fabb824dd1d311e7a1f15",
            sharedSecret: """
                a6b6f11e39b5b0aa89efd008766a7bae2ce99db5814b5b99a98ce7d737a6d27916b342b6373fe8bb\
                15da7d0e3abd8bc8ced88d7b433867defe3dd00f542f2523d549f2156762011c03f1e7c107f6ba8b\
                ac71802b547bb5c12eef8e20fcd308798c9861ae1d9d6cbb3b9295fc312eb1ff18c0bd63272e4c42\
                7345ce0880b4f77dee6c84c49f1520ecdea07e8153097b5ce9f95ae46467b5a7fa131b8196dec613\
                7497475b2f23ff0b2bd8e33564bace7f3d32551e6debd36f2dfacceadbc01e37c7a77c61ad5bf2bc\
                d5496e43668696441bd855b30b8c77ac7e47aacd065703bc1a24eec3d78cfebd4faca7d48cea8c6f\
                2ff6cdfd2a08a8464980b58a477f10efeedee51ced56ceaff2d8cda7f213ec1e3a4308870446edae\
                4ba7f1cdee65494087219cd9c27ae2d7bfe6cbfd288663418dfa2f4377565493756858daacd3bdc0\
                0943be0d38fdee7e0565f825b6823294c712d00098830016762570b3be620537f023fd6786f18197\
                91a43bbb8c7d708f61a1cf19a3bc7390fbefc026457ba347
                """,
            sessionKey: "00a3e2e4f5be70e89fe87c51609f829bbcee1b51203a936b8c9be8b55a4f51e7",
            clientProof: "6b3cb2cd6148c47f2b2c1f9126e1d75fbb592576a5689511e77d1ba5fd960e8c",
            serverProof: "4e3ec5b4e95ade484cf93b2b8b3f340600eada28ab97bfc35ef126048a27b13d"
        ),
    ]

    func testSolutionsMatchTheReferenceImplementation() throws {
        for vector in Self.vectors {
            let client = ApplePasswordsSRPClient(
                identity: Self.identity,
                privateKey: Data(testHexadecimal: vector.privateKey)
            )
            XCTAssertEqual(client.publicKey, Data(testHexadecimal: vector.clientPublicKey), vector.name)

            let solution = try client.solve(
                serverPublicKey: Data(testHexadecimal: vector.serverPublicKey),
                salt: Data(testHexadecimal: Self.salt),
                code: Self.code
            )
            XCTAssertEqual(solution.scrambler, Data(testHexadecimal: vector.scrambler), vector.name)
            XCTAssertEqual(solution.multiplier, Data(testHexadecimal: Self.multiplier), vector.name)
            XCTAssertEqual(solution.privateExponent, Data(testHexadecimal: Self.privateExponent), vector.name)
            XCTAssertEqual(solution.sharedSecret, Data(testHexadecimal: vector.sharedSecret), vector.name)
            XCTAssertEqual(solution.sessionKey, Data(testHexadecimal: vector.sessionKey), vector.name)
            XCTAssertEqual(solution.clientProof, Data(testHexadecimal: vector.clientProof), vector.name)
            XCTAssertEqual(solution.expectedServerProof, Data(testHexadecimal: vector.serverProof), vector.name)
            XCTAssertTrue(solution.verifies(serverProof: Data(testHexadecimal: vector.serverProof)), vector.name)
        }
    }

    func testVectorsCoverTheShortEncodings() throws {
        let width = ApplePasswordsSRPClient.groupLength
        for vector in Self.vectors {
            let client = ApplePasswordsSRPClient(
                identity: Self.identity,
                privateKey: Data(testHexadecimal: vector.privateKey)
            )
            let solution = try client.solve(
                serverPublicKey: Data(testHexadecimal: vector.serverPublicKey),
                salt: Data(testHexadecimal: Self.salt),
                code: Self.code
            )
            switch vector.name {
            case "shortA": XCTAssertEqual(client.publicKey.count, width - 1)
            case "shortB": XCTAssertEqual(Data(testHexadecimal: vector.serverPublicKey).count, width - 1)
            case "shortS": XCTAssertEqual(solution.sharedSecret.count, width - 1)
            case "leadingZeroK": XCTAssertEqual(solution.sessionKey.first, 0)
            default: XCTAssertEqual(client.publicKey.count, width)
            }
        }
    }

    func testAServerProofThatDiffersInOneBitDoesNotVerify() throws {
        let vector = Self.vectors[0]
        let client = ApplePasswordsSRPClient(
            identity: Self.identity,
            privateKey: Data(testHexadecimal: vector.privateKey)
        )
        let solution = try client.solve(
            serverPublicKey: Data(testHexadecimal: vector.serverPublicKey),
            salt: Data(testHexadecimal: Self.salt),
            code: Self.code
        )
        var tampered = Data(testHexadecimal: vector.serverProof)
        tampered[tampered.count - 1] ^= 1
        XCTAssertFalse(solution.verifies(serverProof: tampered))
        XCTAssertFalse(solution.verifies(serverProof: tampered.dropLast()))
    }

    func testAChallengeOutsideTheGroupIsRefused() {
        let client = ApplePasswordsSRPClient(identity: Self.identity, privateKey: Data(repeating: 7, count: 32))
        let salt = Data(testHexadecimal: Self.salt)
        let groupPrime = Data(repeating: 0xFF, count: ApplePasswordsSRPClient.groupLength)
        for publicKey in [Data([0]), Data(), groupPrime] {
            XCTAssertThrowsError(try client.solve(serverPublicKey: publicKey, salt: salt, code: Self.code)) {
                XCTAssertEqual($0 as? ApplePasswordsPairingError, .invalidChallenge)
            }
        }
        XCTAssertThrowsError(
            try client.solve(
                serverPublicKey: Data(testHexadecimal: Self.vectors[0].serverPublicKey),
                salt: Data(),
                code: Self.code
            )
        )
    }
}
