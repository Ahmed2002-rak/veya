"""
VEYA — Sample report fixture                         sample_report.py
=====================================================================

Returns a hardcoded diagnostic report that matches the real server
response shape.  Used by the load_sample_report WS command so
ReportScreen can be exercised visually without a live server tunnel.
"""
from __future__ import annotations

from typing import Any, Dict


def get_sample_report() -> Dict[str, Any]:
    return {
        "schema":    1,
        "report_id": "rpt_SAMPLE_001",
        "ts_iso":    "2026-05-21T10:30:00Z",
        "severity":  "warning",
        "summary": (
            "Rapport de démonstration — données simulées. "
            "Deux codes défaut ont été détectés : un raté d'allumage sur le cylindre 1 "
            "(P0301) et une efficacité insuffisante du catalyseur côté conducteur (P0420). "
            "Une inspection mécanique est recommandée dans les meilleurs délais."
        ),
        "dtc_analyses": [
            {
                "code":        "P0301",
                "severity":    "warning",
                "status":      "actif",
                "title":       "Raté d'allumage détecté — Cylindre 1",
                "description": (
                    "Le calculateur moteur a enregistré des ratés d'allumage répétés sur le "
                    "cylindre numéro 1. Ce défaut peut provoquer une augmentation des émissions, "
                    "une perte de puissance et, à terme, endommager le convertisseur catalytique."
                ),
                "probable_causes": [
                    "Bougie d'allumage défectueuse ou encrassée (cylindre 1)",
                    "Bobine d'allumage défaillante sur le cylindre 1",
                    "Injecteur bouché ou ne s'ouvrant pas correctement",
                    "Fuite de compression dans le cylindre 1 (soupape, segment ou joint de culasse)",
                    "Capteur de position vilebrequin (CKP) donnant un signal erratique",
                ],
                "symptoms": [
                    "Moteur qui tremble ou vibre au ralenti",
                    "Voyant moteur allumé (parfois clignotant)",
                    "Consommation de carburant augmentée",
                    "Perte de puissance notable à l'accélération",
                    "Odeur de carburant non brûlé à l'échappement",
                ],
                "recommended_actions": [
                    "Remplacer la bougie d'allumage du cylindre 1 en priorité",
                    "Tester et, si nécessaire, remplacer la bobine d'allumage du cylindre 1",
                    "Effectuer un test de compression pour écarter un problème mécanique interne",
                    "Vérifier le débit et l'étanchéité de l'injecteur correspondant",
                    "Contrôler les fils et connecteurs du circuit d'allumage du cylindre 1",
                    "Effacer le code après réparation et effectuer un cycle de conduite de validation",
                ],
            },
            {
                "code":        "P0420",
                "severity":    "warning",
                "status":      "actif",
                "title":       "Efficacité du catalyseur insuffisante — Banque 1",
                "description": (
                    "Le système de contrôle des émissions a détecté que l'efficacité du "
                    "convertisseur catalytique de la banque 1 est inférieure au seuil réglementaire. "
                    "Le catalyseur ne parvient plus à oxyder suffisamment les hydrocarbures imbrûlés "
                    "et le monoxyde de carbone issus de la combustion."
                ),
                "probable_causes": [
                    "Catalyseur vieilli ou empoisonné par des additifs carburant à base de plomb",
                    "Ratés d'allumage prolongés ayant surchauffé et détérioré le substrat céramique",
                    "Sonde lambda aval (post-catalyseur) défectueuse donnant une lecture incorrecte",
                    "Fuite d'huile ou de liquide de refroidissement dans les gaz d'échappement",
                    "Capteur lambda amont (pré-catalyseur) usé faussant la régulation air/carburant",
                ],
                "symptoms": [
                    "Voyant moteur allumé en continu",
                    "Émissions de CO et HC supérieures aux normes au contrôle technique",
                    "Légère augmentation de la consommation de carburant",
                    "Possible odeur d'œuf pourri (H₂S) à l'échappement lors des décélérations",
                ],
                "recommended_actions": [
                    "Vérifier et corriger tout code de raté d'allumage avant de remplacer le catalyseur",
                    "Tester les sondes lambda amont et aval (tensions, temps de réponse)",
                    "Inspecter l'échappement pour détecter des fuites en amont du catalyseur",
                    "Contrôler l'absence de consommation d'huile ou de liquide de refroidissement",
                    "Remplacer le convertisseur catalytique si les diagnostics précédents sont négatifs",
                    "Après remplacement, effectuer plusieurs cycles de chauffe pour initialiser le nouveau catalyseur",
                ],
            },
        ],
        "recommendations": [
            "Consulter un mécanicien agréé pour un diagnostic approfondi avant tout long trajet",
            "Ne pas retarder la réparation du P0301 — les ratés d'allumage accélèrent la dégradation du catalyseur",
            "Utiliser exclusivement du carburant sans plomb conforme aux spécifications du fabricant",
            "Planifier une révision complète (bougies, filtres, huile) si le kilométrage le justifie",
        ],
    }
