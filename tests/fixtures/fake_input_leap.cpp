// SPDX-License-Identifier: MIT
// Stand-in for the Input Leap GUI: prints the addresses Qt reports, the
// arguments received, LD_PRELOAD as seen by the process, and exits with the
// code given via --exit N.
#include <QCoreApplication>
#include <QHostAddress>
#include <QNetworkInterface>
#include <cstdio>
#include <cstdlib>
#include <cstring>

int main(int argc, char **argv)
{
    int code = 0;
    for (int i = 1; i < argc; ++i) {
        std::printf("ARG %s\n", argv[i]);
        if (!std::strcmp(argv[i], "--exit") && i + 1 < argc)
            code = std::atoi(argv[i + 1]);
    }
    for (const QHostAddress &a : QNetworkInterface::allAddresses())
        std::printf("ADDR %s\n", a.toString().toStdString().c_str());
    const char *p = std::getenv("LD_PRELOAD");
    std::printf("PRELOAD %s\n", p ? p : "");
    return code;
}
