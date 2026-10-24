# Foco

App de foco e bloqueio de apps para **Android e iOS** (Flutter), com **Parceiro de confiança**:
a senha e a permissão de desbloqueio ficam no celular de outra pessoa.

Projeto original, escrito do zero. Não usa código, marca nem assets de nenhum app existente.

## Recursos

| Recurso | Android | iOS |
|---|---|---|
| Bloqueio de apps | Accessibility Service + tela de bloqueio | FamilyControls / ManagedSettings (Shield) |
| Sessões de foco com timer e streak | ✅ | ✅ |
| Agendamentos recorrentes | ✅ (checados no serviço) | ✅ (extensão DeviceActivityMonitor) |
| Perfis de foco | ✅ | ✅ |
| Limite diário por app | ✅ (UsageStats) | ⚠️ não implementado (exige extensão de relatório) |
| Bloqueio por localização | ✅ (última posição conhecida) | ⚠️ só Android nesta versão |
| Estatísticas de uso | ✅ | ⚠️ iOS não entrega uso por app ao app principal |
| Modo rígido | ✅ | ✅ |
| Proteção contra desinstalar | ✅ Device Admin + guarda das telas do sistema | ❌ o iOS não permite (ver abaixo) |
| **Parceiro de confiança** | ✅ | ✅ |

## Como o Parceiro de confiança funciona

1. **Dono** abre a aba *Parceiro* → *Convidar* → aparece um QR.
2. **Parceiro** instala o app, escolhe *Sou o parceiro* e escaneia o QR. Cria um **PIN que fica só no celular dele** (armazenamento seguro).
3. Quando o dono tenta abrir um app bloqueado, encerrar a sessão, afrouxar regras ou desinstalar, o app cria um **pedido** no Firestore e o parceiro recebe um push.
4. O parceiro confere o motivo, escolhe o tempo (5 min a 12 h) e aprova com **PIN + biometria/senha do aparelho dele**.
5. O aparelho do dono recebe uma liberação temporária que expira sozinha.

O dono nunca tem a senha. As `firebase/firestore.rules` impedem que o dono aprove os próprios pedidos, apague o pareamento ou estenda a liberação além de 12 h. Só o parceiro encerra o pareamento.

## Montando o projeto

Requisitos: Flutter 3.24+, Android Studio, e (para iOS) um Mac com Xcode 15+.

```bash
flutter create --org com.foco --project-name foco .   # gera android/ e ios/ (rodar dentro da pasta foco)
# copie os arquivos de overlay por cima do projeto gerado:
cp -R android_overlay/app/src/main/* android/app/src/main/
cp -R ios_overlay/Runner/* ios/Runner/
flutter pub get
```

### Firebase (necessário para o Parceiro)

1. Crie um projeto em https://console.firebase.google.com e ative **Authentication → Anônimo**, **Firestore** e **Cloud Messaging**.
2. Rode `flutterfire configure` (ou baixe `google-services.json` para `android/app/` e `GoogleService-Info.plist` para `ios/Runner/`).
3. Publique as regras e as funções:
   ```bash
   cd firebase
   firebase deploy --only firestore:rules,functions
   ```
   (Cloud Functions exige o plano Blaze; sem ele o app funciona, mas o parceiro não recebe push e precisa abrir o app para ver os pedidos.)
4. Android: adicione o plugin `com.google.gms.google-services` no Gradle, conforme a documentação do Firebase.
5. iOS: faça upload da chave APNs no Firebase para os pushes.

### Android

- `applicationId`/pacote: `com.foco.app` (os arquivos Kotlin usam esse pacote; se mudar, ajuste o `package` neles).
- Ao abrir o app, conceda: **Acessibilidade**, **Acesso ao uso**, **Sobrepor outros apps** e **Administrador do dispositivo**.
- Para publicar na Play Store, a política de AccessibilityService exige declaração de uso e vídeo de demonstração.

### iOS

1. O entitlement **Family Controls (Distribution)** exige solicitação e aprovação da Apple: https://developer.apple.com/contact/request/family-controls-distribution. Em desenvolvimento, funciona com o entitlement de desenvolvimento.
2. No Xcode: ative as capabilities **Family Controls**, **App Groups** (`group.com.foco.app`), **Push Notifications** e **Background Modes → Remote notifications** no target Runner.
3. Adicione um novo target **Device Activity Monitor Extension** e use o arquivo `ios_overlay/FocoMonitor/FocoMonitor.swift`. Ative nele também Family Controls e o mesmo App Group.
4. Defina `NSFaceIDUsageDescription` e `NSCameraUsageDescription` no `Info.plist`.

## Limites honestos

- **Nenhum app consegue ser à prova de dono.** No Android, o dono ainda pode reiniciar em modo seguro ou fazer reset de fábrica. A guarda das telas de Configurações e o Device Admin dificultam bastante o caminho comum.
- **iOS não permite proteção contra desinstalação por apps.** A solução recomendada: o **parceiro define o código do Tempo de Uso** no iPhone do dono (Ajustes → Tempo de Uso → Usar Código) e o app autoriza com `.individual`; assim, remover restrições ou apagar apps exige o código que só o parceiro sabe.
- Sem internet, não há como pedir liberação, o que, neste caso, é o comportamento desejado.
- Não foi possível compilar nem testar neste ambiente (sem Flutter/Android SDK/Xcode). O código foi escrito com cuidado, mas espere pequenos ajustes de compilação no primeiro build.

## Estrutura

```
lib/                  App Flutter (telas, estado, serviço do parceiro, ponte nativa)
android_overlay/      Kotlin: serviço de bloqueio, tela de bloqueio, Device Admin, manifest
ios_overlay/          Swift: FamilyControls, seletor de apps, extensão de agenda
firebase/             Regras do Firestore e Cloud Functions de notificação
```
