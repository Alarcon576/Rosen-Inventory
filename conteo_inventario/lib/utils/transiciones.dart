// transiciones.dart
// Transiciones de navegación ligeras y reutilizables.
//
// Son baratas en recursos: usan las animaciones que Flutter ya corre
// al empujar una ruta (no crean AnimationControllers extra ni redibujan
// de más). Se usan así:
//
//   Navigator.push(context, rutaFade(MiPantalla()));
//   Navigator.pushReplacement(context, rutaFade(MiPantalla()));

import 'package:flutter/material.dart';

// Transición de aparición suave (fade) + un leve desplazamiento hacia
// arriba. Duración corta para que se sienta ágil.
Route<T> rutaFade<T>(Widget pantalla) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, __, ___) => pantalla,
    transitionsBuilder: (_, animation, __, child) {
      final curva = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curva,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(curva),
          child: child,
        ),
      );
    },
  );
}

// Transición pensada para acompañar un Hero (logo que "vuela" entre
// pantallas): fade + un ligero zoom del contenido. Dura un poco más
// para que el vuelo del Hero se aprecie. Sigue siendo barata: solo usa
// la animación de la ruta, sin controladores extra.
Route<T> rutaFadeEscala<T>(Widget pantalla) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 550),
    reverseTransitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (_, __, ___) => pantalla,
    transitionsBuilder: (_, animation, __, child) {
      final curva = CurvedAnimation(parent: animation, curve: Curves.easeInOut);
      return FadeTransition(
        opacity: curva,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curva),
          child: child,
        ),
      );
    },
  );
}