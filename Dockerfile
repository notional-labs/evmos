FROM ghcr.io/notional-labs/evmos

RUN pacman -Syyu --noconfirm go base-devel

COPY . .

CMD bash ss.bash
