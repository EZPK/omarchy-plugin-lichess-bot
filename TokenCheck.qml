import QtQuick
import Quickshell.Io

// Checks a Lichess API token against GET /api/account: a request with no
// body, only an Authorization header. The header-only path was reliable
// throughout this plugin's curl debugging (every test, working or not,
// correctly reached Lichess's auth layer — "No such token" for a bad
// token, real x-oauth-scopes response headers for a good one); it was
// specifically request *bodies* that curl-as-a-Quickshell-child could
// not get through intact, which is why game creation itself now goes
// through a browser instead (see webapp/launch.html). A bodyless GET
// doesn't hit that path at all.
Process {
  id: root

  readonly property string script:
    "exec curl -s --http1.1 --oauth2-bearer \"$LB_TOKEN\" -w \"HTTPSTATUSMARKER:%{http_code}\" \"https://lichess.org/api/account\""

  property string buffer: ""

  signal finished(string output)

  stdout: SplitParser {
    onRead: function(line) { root.buffer += line + "\n" }
  }

  onExited: function(exitCode, exitStatus) {
    var text = root.buffer
    root.buffer = ""
    root.finished(text)
  }

  function run(token) {
    root.buffer = ""
    root.exec({
      command: ["sh", "-c", root.script],
      environment: { LB_TOKEN: token }
    })
  }
}
