using Microsoft.Win32;
using System.Runtime.InteropServices;

namespace GHelper.UI
{
    public class RForm : Form
    {

        public static Color colorEco = Color.FromArgb(255, 6, 180, 138);
        public static Color colorStandard = Color.FromArgb(255, 58, 174, 239);
        public static Color colorTurbo = Color.FromArgb(255, 255, 32, 32);
        public static Color colorCustom = Color.FromArgb(255, 255, 128, 0);
        public static Color colorGray = Color.FromArgb(255, 168, 168, 168);


        public static Color buttonMain;
        public static Color buttonSecond;

        public static Color formBack;
        public static Color foreMain;
        public static Color borderMain;
        public static Color borderSecond;
        public static Color chartMain;
        public static Color chartGrid;

        public static bool flatTheme = false;

        [DllImport("UXTheme.dll", SetLastError = true, EntryPoint = "#138")]
        public static extern bool CheckSystemDarkModeStatus();

        [DllImport("UXTheme.dll", SetLastError = true, EntryPoint = "#135")]
        private static extern int SetPreferredAppMode(int preferredAppMode);

        [DllImport("UXTheme.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern int SetWindowTheme(nint hWnd, string pszSubAppName, string? pszSubIdList);

        [DllImport("DwmApi")] //System.Runtime.InteropServices
        private static extern int DwmSetWindowAttribute(nint hwnd, int attr, int[] attrValue, int attrSize);

        public bool darkTheme = false;
        private bool themeInitialized = false;

        public RForm()
        {
            // Reduce flicker / progressive paint: double-buffer whole form
            // Pre-fill with dark background BEFORE handle created to avoid white DWM surface flash (grey-black app shows white holes)
            var earlyDark = IsDarkTheme();
            BackColor = earlyDark ? Color.FromArgb(255, 28, 28, 28) : SystemColors.Control;
            ForeColor = earlyDark ? Color.FromArgb(255, 240, 240, 240) : SystemColors.ControlText;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            DoubleBuffered = true;
            UpdateStyles();
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            // Set immersive dark title bar BEFORE visible to avoid white title flash
            try
            {
                bool isDark = darkTheme || IsDarkTheme();
                DwmSetWindowAttribute(Handle, 20, new[] { isDark ? 1 : 0 }, 4);
            }
            catch { }
            base.OnHandleCreated(e);
        }

        protected override void WndProc(ref Message m)
        {
            // Suppress WM_ERASEBKGND white fill - we paint entire background in OnPaint/DoubleBuffered
            // This removes the jarring white boxes flash before dark theme applied
            if (m.Msg == 0x0014) // WM_ERASEBKGND
            {
                m.Result = (IntPtr)1;
                return;
            }
            base.WndProc(ref m);
        }

        protected override CreateParams CreateParams
        {
            get
            {
                var parms = base.CreateParams;
                // Keep WS_CLIPCHILDREN (0x02000000) - prevents parent from over-painting child areas
                parms.Style |= 0x02000000;
                // First fix was best: WS_EX_COMPOSITED hides white sketch by buffering whole window off-screen
                // then popping fully rendered. Keep it but with dark BackColor pre-fill + WM_ERASEBKGND suppression
                // to avoid blue delay. Blank bottom was from AutoSize=false, not composited.
                parms.ExStyle |= 0x02000000; // WS_EX_COMPOSITED
                parms.ClassStyle &= ~0x00020000; // CS_DROPSHADOW off
                return parms;
            }
        }
        public static void InitColors(bool darkTheme)
        {
            flatTheme = AppConfig.GetString("theme")?.ToLower() == "flat";

            if (darkTheme)
            {
                buttonMain = Color.FromArgb(255, 46, 46, 46);
                buttonSecond = Color.FromArgb(255, 36, 36, 36);

                formBack = Color.FromArgb(255, 28, 28, 28);
                foreMain = Color.FromArgb(255, 240, 240, 240);
                borderMain = Color.FromArgb(255, 55, 55, 55);
                borderSecond = Color.FromArgb(255, 42, 42, 42);

                chartMain = Color.FromArgb(255, 35, 35, 35);
                chartGrid = Color.FromArgb(255, 70, 70, 70);
            }
            else
            {
                buttonMain = SystemColors.ControlLightLight;
                buttonSecond = SystemColors.ControlLight;

                formBack = SystemColors.Control;
                foreMain = SystemColors.ControlText;
                borderMain = Color.FromArgb(255, 220, 220, 220);
                borderSecond = Color.FromArgb(255, 215, 215, 215);

                chartMain = SystemColors.ControlLightLight;
                chartGrid = Color.LightGray;
            }
        }

        private static bool IsDarkTheme()
        {
            string? uiMode = AppConfig.GetString("ui_mode");

            if (uiMode is not null && uiMode.ToLower() == "dark")
            {
                return true;
            }

            if (uiMode is not null && uiMode.ToLower() == "light")
            {
                return false;
            }

            if (uiMode is not null && uiMode.ToLower() == "windows")
            {
                return CheckSystemDarkModeStatus();
            }

            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            var registryValueObject = key?.GetValue("AppsUseLightTheme");

            if (registryValueObject == null) return false;
            return (int)registryValueObject <= 0;
        }

        public bool InitTheme(bool setDPI = false)
        {
            bool newDarkTheme = IsDarkTheme();
            bool changed = darkTheme != newDarkTheme;
            bool firstInit = !themeInitialized;
            darkTheme = newDarkTheme;
            themeInitialized = true;

            InitColors(darkTheme);

            if (setDPI)
                ControlHelper.Resize(this);

            if (changed || firstInit)
            {
                DwmSetWindowAttribute(Handle, 20, new[] { darkTheme ? 1 : 0 }, 4);
                SetPreferredAppMode(darkTheme ? 1 : 0); 
                SetWindowTheme(Handle, darkTheme ? "DarkMode_Explorer" : "Explorer", null);
                ControlHelper.Adjust(this, changed);
                this.Invalidate();
            }


            return changed;

        }

    }
}
