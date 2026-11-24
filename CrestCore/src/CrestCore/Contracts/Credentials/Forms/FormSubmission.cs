using System.Text.RegularExpressions;

namespace CrestCore.Contracts;

/// How a form was sent: its `Trigger`, whether its fields sit in a form
/// element, and the label of the control the person pressed, empty for none.
public sealed record FormSubmission(SubmitTrigger Trigger, bool InFormElement, string ControlLabel) {
    #region Static Variables

    /// Labels of controls that send a sign-in, sign-up or password change, in
    /// the languages Crest's patterns cover.
    private static readonly Regex SendingLabel = new(
        @"^\W*(sign|log)[\s-]*(in|on|up)\b|^\W*(login|continue(?!\s+(as\s+)?guest)|next|submit|register|create|join|save|change|update|reset|set password|confirm|verify)\b|^\W*(anmelden|einloggen|weiter|registrieren|speichern|ändern|se connecter|connexion|continuer|suivant|s'inscrire|valider|iniciar sesión|entrar|continuar|siguiente|registrarse|guardar|accedi|continua|avanti|registrati|salva|inloggen|aanmelden|doorgaan|volgende|opslaan)\b",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    #endregion

    #region Variables

    /// Whether this sends the form: its trigger always does where it is, or
    /// the control's label says it does.
    internal bool SendsForm =>
        (InFormElement ? Trigger.SendsForm : Trigger.SendsOtherScope) || SendingLabel.IsMatch(ControlLabel);

    #endregion
}
