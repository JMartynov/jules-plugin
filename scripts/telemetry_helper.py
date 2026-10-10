import json
import logging

def export_telemetry_json(telemetry_data, output_filepath):
    """
    Exports telemetry data to a JSON file.
    
    Args:
        telemetry_data (dict): The telemetry data to export.
        output_filepath (str): The path to the output JSON file.
    """
    try:
        with open(output_filepath, 'w') as f:
            json.dump(telemetry_data, f, indent=4)
        logging.info(f"Successfully exported telemetry data to {output_filepath}")
        return True
    except Exception as e:
        logging.error(f"Failed to export telemetry data to {output_filepath}: {e}")
        return False
