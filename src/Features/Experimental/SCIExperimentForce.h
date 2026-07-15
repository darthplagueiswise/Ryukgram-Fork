// SCIExperimentForce — hooks do framework de experiments unificado da build 438.
//
// Cobre as três superfícies novas mapeadas contra Instagram/FBSharedFramework 438:
//
//   G1. Managers unificados de experiment (o mecanismo genérico mais poderoso):
//         FBCCIGExperimentManager / FBCustomExperimentManager
//         -isFeatureEnabled:(uint64) / -isFeatureEnabledWithoutLogging:(uint64)
//         -getFeatureIntValue:(uint64) / -getFeatureIntValueWithoutLogging:(uint64)
//       Estrutura idêntica ao getBool:(mc_bool_param_t) do MobileConfig: recebe um
//       feature ID (uint64) e retorna o valor. Por isso NÃO forçamos cego — reusamos
//       o mesmo sistema de captura + override SELETIVO por ID do SCIMobileConfigRuntime
//       (recordParamID:/overrideForParamID:). Forçar YES em todos os IDs quebraria o
//       app (experiments conflitantes/mutuamente exclusivos).
//
//   G2. QuickExperiment configs (padrão *ExperimentConfig):
//         +[<Nome>ExperimentConfig isEnabled:(id)context]  (class method, B24@0:8@16)
//       Cada classe é UM experimento nomeado, então forçar YES por classe é granular e
//       seguro. Descoberta é dinâmica (varre todas as classes cujo nome termina em
//       "ExperimentConfig" e que têm +isEnabled:). Override é SELETIVO por nome de
//       classe; há um "forçar todos" atrás de uma pref de risco explícita.
//
//   G3. Helpers de experimento específicos (curados e validados contra 438):
//         IGStoriesTabExperimentHelper, IGDirectNotesExperimentHelper,
//         IGSwiftMigrationExperiment, etc. — métodos is*Enabled[WithLauncherSet:].
//       Forçados SELETIVAMENTE por (classe, seletor) via pref.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void SCIInstallExperimentForceHooksIfNeeded(void);

@interface SCIExperimentForce : NSObject

// Prefs (todas default OFF):
//   sci_exp_mgr_capture   — liga captura dos feature IDs dos managers unificados (G1),
//                           roteada pro mesmo runtime browser do MobileConfig.
//   sci_qe_force_all      — pref de RISCO: força +isEnabled: = YES em TODAS as
//                           *ExperimentConfig (G2). Use com cuidado.
//   sci_qe_force_<Classe>  — força YES só naquela *ExperimentConfig (G2).
//   sci_exp_helpers       — liga os helpers curados (G3).
+ (NSArray<NSString *> *)prefKeys;
+ (BOOL)anyEnabled;

// Nomes das *ExperimentConfig descobertas nesta build (pra popular UI de toggle).
+ (NSArray<NSString *> *)discoveredQuickExperimentConfigNames;

@end

NS_ASSUME_NONNULL_END
