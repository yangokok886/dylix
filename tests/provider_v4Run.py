from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parent.parent
sdk='/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk'
with tempfile.TemporaryDirectory(prefix='provider-v4-') as d:
 binary=Path(d)/'tests'
 cmd=['/usr/bin/clang','-isysroot',sdk,'-fobjc-arc','-DTFAI_TRANSPORT_TESTING=1','-Wno-incompatible-pointer-types','-Wno-nullability-completeness',str(root/'tests/provider_v4Tests.m'),str(root/'App/AI/Providers/TFAIProtocol.m'),str(root/'App/AI/Providers/TFAIConnections.m'),str(root/'App/AI/Transport/TFAITransport.m'),str(root/'App/AI/Transport/TFAINetworkDiagnostics.m'),'-framework','Foundation','-framework','Security','-framework','CoreGraphics','-framework','ImageIO','-o',str(binary)]
 subprocess.run(cmd,check=True)
 subprocess.run([str(binary),'--ai-runtime-test'],check=True)
